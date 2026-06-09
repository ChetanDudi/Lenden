import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:math';
import '../session.dart';
import '../utils/api_client.dart';

class AdminManagementPage extends StatefulWidget {
  const AdminManagementPage({Key? key}) : super(key: key);

  @override
  _AdminManagementPageState createState() => _AdminManagementPageState();
}

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.8);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height,
      size.width * 0.5,
      size.height * 0.8,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.6,
      size.width,
      size.height * 0.8,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
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
                  color: Colors.black.withOpacity(0.1),
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
                            color: Colors.grey.withOpacity(0.1),
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
                                color: Colors.grey.withOpacity(0.1),
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
                                color: Colors.grey.withOpacity(0.1),
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
                            color: Colors.grey.withOpacity(0.1),
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
                            color: Colors.grey.withOpacity(0.1),
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
                                    final session =
                                        Provider.of<SessionProvider>(context,
                                            listen: false);

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
                                Color(0xFF00B4D8).withOpacity(0.5),
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
                    .withOpacity(0.3),
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
                        color: Colors.black.withOpacity(0.05),
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
                                                  .withOpacity(0.2),
                                              width: 1,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.03),
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
                                                          Text(
                                                            admin['name'],
                                                            style: TextStyle(
                                                              fontSize: 18,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                          SizedBox(height: 4),
                                                          Text(
                                                            admin['email'],
                                                            style: TextStyle(
                                                              color: Colors.grey
                                                                  .shade600,
                                                            ),
                                                          ),
                                                          Text(
                                                            '@${admin['username']}',
                                                            style: TextStyle(
                                                              color: Colors.grey
                                                                  .shade500,
                                                              fontSize: 13,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    if (!isProtected)
                                                      IconButton(
                                                        icon: Icon(
                                                            Icons
                                                                .delete_outline,
                                                            color: Colors.red),
                                                        onPressed: () =>
                                                            _showDeleteConfirmation(
                                                                admin),
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
                                                          .withOpacity(0.7),
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
                      color: Colors.black.withOpacity(0.1),
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
