import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/http_interceptor.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _birthdayController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late TextEditingController _addressController;
  String? _gender;
  Uint8List? _newImageBytes;
  bool _removeImage = false;
  int _imageRefreshKey = 0; // Key to force avatar rebuild
  bool _isUpdating = false; // Loading state for profile update

  @override
  void initState() {
    super.initState();
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    _nameController = TextEditingController(text: user?['name'] ?? '');
    String birthday = user?['birthday'] ?? '';
    if (birthday.contains('T')) {
      birthday = birthday.split('T').first;
    }
    _birthdayController = TextEditingController(text: birthday);
    _phoneController = TextEditingController(text: user?['phone'] ?? '');
    _emailController = TextEditingController(text: user?['email'] ?? '');
    _passwordController = TextEditingController();
    _addressController = TextEditingController(text: user?['address'] ?? '');
    _gender = user?['gender'] ?? 'Other';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _birthdayController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        final File imageFile = File(image.path);
        final Uint8List imageBytes = await imageFile.readAsBytes();

        setState(() {
          _newImageBytes = imageBytes;
          _removeImage = false;
          _imageRefreshKey++; // Force avatar rebuild
        });
      }
    } catch (e) {
      showSnack(context, 'Error picking image: $e', isError: true);
    }
  }

  void _removeProfileImage() {
    setState(() {
      _newImageBytes = null;
      _removeImage = true;
      _imageRefreshKey++; // Force avatar rebuild
    });
  }

  void _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isUpdating = true;
    });

    final session = Provider.of<SessionProvider>(context, listen: false);
    final isAdmin = session.isAdmin;
    final url = isAdmin ? '/api/admins/me' : '/api/users/me';

    try {
      final request = await HttpInterceptor.multipartRequest('PUT', url);
      request.fields['name'] = _nameController.text;
      request.fields['birthday'] = _birthdayController.text;
      request.fields['phone'] = _phoneController.text;
      request.fields['address'] = _addressController.text;
      request.fields['gender'] = _gender ?? '';
      if (_removeImage) {
        request.fields['removeImage'] = 'true';
      } else if (_newImageBytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
            'profileImage', _newImageBytes!,
            filename: 'profile.png'));
      }

      final response = await request.send();
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final updatedUser = jsonDecode(respStr);

        session.setUser(updatedUser);
        await session.forceRefreshProfile();

        setState(() {
          _newImageBytes = null;
          _removeImage = false;
          _imageRefreshKey++;
          _isUpdating = false;
        });

        showSnack(context, 'Profile updated successfully!');
      } else {
        setState(() {
          _isUpdating = false;
        });
        showSnack(context, 'Failed to update profile', isError: true);
      }
    } catch (e) {
      setState(() {
        _isUpdating = false;
      });
      showSnack(context, 'Error updating profile: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<SessionProvider>(context).user;
    final gender = _gender ?? 'Other';
    final imageUrl = user?['profileImage'];

    Widget avatar;
    if (_newImageBytes != null) {
      // Show newly selected image
      avatar = CircleAvatar(
        key: ValueKey(_imageRefreshKey),
        radius: 54,
        backgroundImage: MemoryImage(_newImageBytes!),
        backgroundColor: AppColors.cyan,
      );
    } else if (_removeImage ||
        imageUrl == null ||
        imageUrl.toString().isEmpty ||
        imageUrl == 'null') {
      // Show default avatar based on gender
      avatar = CircleAvatar(
        key: ValueKey(_imageRefreshKey),
        radius: 54,
        backgroundImage: AssetImage(
          gender == 'Male'
              ? 'assets/Male.png'
              : gender == 'Female'
                  ? 'assets/Female.png'
                  : 'assets/Other.png',
        ),
        backgroundColor: AppColors.cyan,
      );
    }
    else {
      // Show network image with cache busting for real-time updates
      final cacheBustingUrl =
          '$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      avatar = CircleAvatar(
        key: ValueKey(_imageRefreshKey),
        radius: 54,
        backgroundImage: NetworkImage(cacheBustingUrl),
        backgroundColor: AppColors.cyan,
        onBackgroundImageError: (exception, stackTrace) {
          // Fallback to default avatar if network image fails
        },
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Edit Profile',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Top blue wave — behind AppBar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: _EditProfileWaveClipper(),
              child: Container(
                height: 160,
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
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28.0, vertical: 24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Stack(
                          children: [
                            avatar,
                            if (_isUpdating)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isUpdating ? null : _pickImage,
                            icon: Icon(Icons.upload,
                                color: _isUpdating
                                    ? Colors.grey
                                    : AppColors.cyan),
                            label: Text('Upload',
                                style: TextStyle(
                                    color: _isUpdating
                                        ? Colors.grey
                                        : AppColors.cyan)),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: _isUpdating ? null : _removeProfileImage,
                            icon: Icon(Icons.delete,
                                color: _isUpdating ? Colors.grey : Colors.red),
                            label: Text('Remove',
                                style: TextStyle(
                                    color: _isUpdating
                                        ? Colors.grey
                                        : Colors.red)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _editField(Icons.person, 'Name', _nameController),
                      _editField(Icons.account_circle, 'Username',
                          TextEditingController(text: user?['username'] ?? ''),
                          readOnly: true),
                      _editField(Icons.email, 'Email', _emailController,
                          keyboardType: TextInputType.emailAddress,
                          readOnly: true),
                      _editField(Icons.alternate_email, 'Alternate Email',
                          TextEditingController(text: user?['altEmail'] ?? ''),
                          readOnly: true),
                      _editGenderField(),
                      _editField(Icons.cake, 'Birthday', _birthdayController),
                      _editField(Icons.home, 'Address', _addressController),
                      _editField(Icons.phone, 'Phone', _phoneController),
                      _editField(
                          Icons.calendar_today,
                          'Member Since',
                          TextEditingController(
                              text: (user?['createdAt'] ?? '')
                                  .toString()
                                  .split('T')
                                  .first),
                          readOnly: true),
                      Builder(
                        builder: (context) {
                          final avgRatingNum = (user?['avgRating'] is num)
                              ? (user?['avgRating'] as num?)?.toDouble() ?? 0.0
                              : double.tryParse(
                                      user?['avgRating']?.toString() ?? '') ??
                                  0.0;
                          final avgRating = avgRatingNum > 0
                              ? avgRatingNum.toStringAsFixed(2)
                              : '';
                          return avgRating.isNotEmpty
                              ? Row(
                                  children: [
                                    Expanded(
                                        child: _editField(
                                            Icons.star,
                                            'Avg. Rating',
                                            TextEditingController(
                                                text: avgRating),
                                            readOnly: true)),
                                    Row(
                                      children: List.generate(5, (i) {
                                        if (i < avgRatingNum.floor()) {
                                          return Icon(Icons.star,
                                              color: Color(0xFFFFC107),
                                              size: 22);
                                        } else if (i == avgRatingNum.floor() &&
                                            (avgRatingNum -
                                                    avgRatingNum.floor()) >=
                                                0.25) {
                                          return Icon(Icons.star_half,
                                              color: Color(0xFFFFC107),
                                              size: 22);
                                        } else {
                                          return Icon(Icons.star_border,
                                              color: Color(0xFFFFC107),
                                              size: 22);
                                        }
                                      }),
                                    ),
                                  ],
                                )
                              : Container();
                        },
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: _isUpdating ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isUpdating
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Saving...',
                                      style: TextStyle(
                                          fontSize: 18, color: Colors.white)),
                                ],
                              )
                            : const Text('Save',
                                style: TextStyle(
                                    fontSize: 18, color: Colors.white)),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Cancel',
                            style:
                                TextStyle(fontSize: 18, color: Colors.black87)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
// ...existing code...
  }

  Widget _tricolorBorder({required Widget child, double radius = 16}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 2),
        child: child,
      ),
    );
  }

  Widget _editField(
      IconData icon, String label, TextEditingController controller,
      {TextInputType keyboardType = TextInputType.text,
      bool readOnly = false}) {
    return _tricolorBorder(
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          Icon(icon, color: AppColors.cyan),
          const SizedBox(width: 16),
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              readOnly: readOnly || label == 'Birthday',
              decoration: InputDecoration(
                labelText: label,
                border: InputBorder.none,
                suffixIcon: label == 'Birthday'
                    ? IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: controller.text.isNotEmpty
                                ? DateTime.tryParse(controller.text) ??
                                    DateTime(2000)
                                : DateTime(2000),
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            controller.text =
                                picked.toIso8601String().split('T').first;
                          }
                        },
                      )
                    : null,
              ),
              validator: (val) {
                if (readOnly ||label == 'Birthday' ||
                    label == 'Phone' ||
                    label == 'Address') {
                  return null; // Not required
                }
                return val == null || val.isEmpty ? 'Required' : null;
              },
              onTap: label == 'Birthday'
                  ? () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: controller.text.isNotEmpty
                            ? DateTime.tryParse(controller.text) ??
                                DateTime(2000)
                            : DateTime(2000),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        controller.text =
                            picked.toIso8601String().split('T').first;
                      }
                    }
                  : null,
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _editGenderField() {
    return _tricolorBorder(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.white,
        child: Row(
          children: [
            const Icon(Icons.transgender, color: AppColors.cyan),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _gender,
                decoration: const InputDecoration(
                  labelText: 'Gender',
                  border: InputBorder.none,
                ),
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (val) => setState(() => _gender = val),
                validator: (val) => val == null ? 'Required' : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditProfileWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.75);
    path.cubicTo(
      size.width * 0.25, size.height * 1.05,
      size.width * 0.75, size.height * 0.45,
      size.width, size.height * 0.75,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_) => false;
}

