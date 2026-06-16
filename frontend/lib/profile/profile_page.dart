import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import 'dart:convert';
import '../utils/api_client.dart';
import '../utils/responsive.dart';
import 'edit_profile_page.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';

class ProfilePage extends StatefulWidget {
  final String? email;
  const ProfilePage({Key? key, this.email}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;
  int _imageRefreshKey = 0; // Key to force avatar rebuild

  @override
  void initState() {
    super.initState();
    // Add a small delay to ensure session is properly initialized
    Future.delayed(const Duration(milliseconds: 100), () {
      _fetchProfile();
    });
  }

  Future<void> _fetchProfile() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final user = session.user;

    if (widget.email != null && widget.email!.isNotEmpty) {
      // Fetch profile by email (admin viewing another user)
      final path =
          '/api/users/profile-by-email?email=${Uri.encodeComponent(widget.email!)}';
      try {
        final response = await ApiClient.get(path);
        if (response.statusCode == 200) {
          setState(() {
            _profile = jsonDecode(response.body);
            _loading = false;
            _imageRefreshKey++;
          });
        } else {
          setState(() {
            _error = 'User not found.';
            _profile = null;
            _loading = false;
          });
        }
      } catch (e) {
        setState(() {
          _error = 'Error loading profile.';
          _profile = null;
          _loading = false;
        });
      }
      return;
    }

    if (session.accessToken == null || user == null) {
      setState(() {
        _error = 'Not logged in.';
        _loading = false;
      });
      return;
    }
    final isAdmin = session.isAdmin;
    final path = isAdmin ? '/api/admins/me' : '/api/users/me';
    try {
      final response = await ApiClient.get(path);
      if (response.statusCode == 200) {
        setState(() {
          _profile = jsonDecode(response.body);
          _loading = false;
          _imageRefreshKey++; // Force avatar rebuild
        });
      } else {
        setState(() {
          _error = null;
          _profile = null;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = null;
        _profile = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context);
    final user = _profile ?? session.user;
    final userName = user?['name'] ?? 'User Name';
    final username = user?['username'] ?? '';
    final email = user?['email'] ?? 'user@email.com';
    final altEmail = user?['altEmail'] ?? '';
    final gender = user?['gender'] ?? 'Other';
    final imageUrl = user?['profileImage'];
    final birthday = user?['birthday'] ?? '';
    String birthdayDisplay = birthday;
    if (birthdayDisplay.contains('T')) {
      birthdayDisplay = birthdayDisplay.split('T').first;
    }
    final phone = user?['phone'] ?? '';
    final address = user?['address'] ?? '';
    final memberSince = user?['createdAt'] ?? '';
    String memberSinceDisplay = memberSince;
    if (memberSinceDisplay.contains('T')) {
      memberSinceDisplay = memberSinceDisplay.split('T').first;
    }
    final avgRatingNum = (user?['avgRating'] is num)
        ? (user?['avgRating'] as num?)?.toDouble() ?? 0.0
        : double.tryParse(user?['avgRating']?.toString() ?? '') ?? 0.0;
    final avgRating = avgRatingNum > 0 ? avgRatingNum.toStringAsFixed(2) : '';

    // Choose the correct avatar provider based on imageUrl
    ImageProvider avatarProvider;
    if (imageUrl != null &&
        imageUrl is String &&
        imageUrl.trim().isNotEmpty &&
        imageUrl != 'null') {
      // Add cache busting parameter for real-time updates
      final cacheBustingUrl =
          '$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      avatarProvider = NetworkImage(cacheBustingUrl);
    } else {
      avatarProvider = AssetImage(
        gender == 'Male'
            ? 'assets/Male.png'
            : gender == 'Female'
                ? 'assets/Female.png'
                : 'assets/Other.png',
      );
    }
    final isViewingOwnProfile = widget.email == null || widget.email!.isEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      body: Stack(
        children: [
          // Top blue shape
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: context.sh(110),
                color: AppColors.cyan,
              ),
            ),
          ),
          // Main content scrollable to the end
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(context.hPadding, context.vPadding, context.hPadding, 100.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: context.sh(28)),
                  Center(
                    child: CircleAvatar(
                      key: ValueKey(_imageRefreshKey),
                      radius: context.sw(50),
                      backgroundColor: AppColors.cyan,
                      backgroundImage: avatarProvider,
                      child: null,
                    ),
                  ),
                  SizedBox(height: context.sh(16)),
                  Center(
                    child: Text(
                      userName,
                      style: TextStyle(
                          fontSize: context.sp(22),
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                    ),
                  ),
                  SizedBox(height: context.sh(22)),
                  if (userName.isNotEmpty)
                    _profileField(Icons.person, 'Name', userName),
                  if (username.isNotEmpty)
                    _profileField(Icons.account_circle, 'Username', username),
                  if (email.isNotEmpty)
                    _profileField(Icons.email, 'Email', email),
                  if (altEmail.isNotEmpty)
                    _profileField(
                        Icons.alternate_email, 'Alternate Email', altEmail),
                  if (gender.isNotEmpty)
                    _profileField(Icons.transgender, 'Gender', gender),
                  if (birthday.isNotEmpty)
                    _profileField(Icons.cake, 'Birthday', birthdayDisplay),
                  if (address.isNotEmpty)
                    _profileField(Icons.home, 'Address', address),
                  if (phone.isNotEmpty)
                    _profileField(Icons.phone, 'Phone', phone),
                  if (memberSince.isNotEmpty)
                    _profileField(Icons.calendar_today, 'Member Since',
                        memberSinceDisplay),
                  if (avgRating.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                            child: _profileField(
                                Icons.star, 'Avg. Rating', avgRating)),
                        Row(
                          children: List.generate(5, (i) {
                            if (i < avgRatingNum.floor()) {
                              return Icon(Icons.star,
                                  color: const Color(0xFFFFC107), size: context.sp(20));
                            } else if (i == avgRatingNum.floor() &&
                                (avgRatingNum - avgRatingNum.floor()) >= 0.25) {
                              return Icon(Icons.star_half,
                                  color: const Color(0xFFFFC107), size: context.sp(20));
                            } else {
                              return Icon(Icons.star_border,
                                  color: const Color(0xFFFFC107), size: context.sp(20));
                            }
                          }),
                        ),
                      ],
                    ),
                  const SizedBox(height: 32),
                  if (isViewingOwnProfile) ...[
                    ElevatedButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const EditProfilePage()),
                        );
                        // Force refresh profile after editing to get updated image
                        final session = Provider.of<SessionProvider>(context,
                            listen: false);
                        await session.forceRefreshProfile();
                        setState(() {
                          _imageRefreshKey++; // Force avatar rebuild
                        });
                        _fetchProfile();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        padding: EdgeInsets.symmetric(vertical: context.sh(14)),
                      ),
                      child: Text('Edit profile',
                          style: TextStyle(fontSize: context.sp(17), color: Colors.white)),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pushNamed(context, '/settings');
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: AppColors.cyan, width: 2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        padding: EdgeInsets.symmetric(vertical: context.sh(14)),
                      ),
                      child: Text('Settings',
                          style: TextStyle(
                              fontSize: context.sp(17), color: AppColors.cyan)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Center(child: Text(_error!, style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _profileField(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Row(
            children: [
              Icon(icon, color: AppColors.cyan),
              const SizedBox(width: 16),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$label: ',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: context.sp(15)),
                      ),
                      TextSpan(
                        text: value,
                        style: TextStyle(
                            fontSize: context.sp(15),
                            fontWeight: FontWeight.normal),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height * 0.7);
    path.quadraticBezierTo(
        size.width * 0.25, size.height, size.width * 0.5, size.height * 0.7);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.4, size.width, size.height * 0.7);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

