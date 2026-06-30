import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import 'dart:convert';
import '../utils/api_client.dart';
import '../utils/responsive.dart';
import 'edit_profile_page.dart';
import '../widgets/app_colors.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';
import '../widgets/wave_widget.dart' show DeepTopWaveClipper;
import '../widgets/avatar_action_sheet.dart';


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
            _error = AppLocalizations.of(context).t('user_not_found');
            _profile = null;
            _loading = false;
          });
        }
      } catch (e) {
        setState(() {
          _error = AppLocalizations.of(context).t('error_loading_profile');
          _profile = null;
          _loading = false;
        });
      }
      return;
    }

    if (session.accessToken == null || user == null) {
      setState(() {
        _error = AppLocalizations.of(context).t('not_logged_in_period');
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
    final t = AppLocalizations.of(context).t;
    final session = Provider.of<SessionProvider>(context);
    final user = _profile ?? session.user;
    final userName = user?['name'] ?? t('user_name_fallback');
    final username = user?['username'] ?? '';
    final email = user?['email'] ?? t('user_email_fallback');
    final altEmail = user?['altEmail'] ?? '';
    final gender = user?['gender'] ?? t('other');
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
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          // Top blue shape
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: const DeepTopWaveClipper(),
              child: Container(
                height: context.sh(78),
                color: AppThemeColors.waveSolid(context),
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
                    child: GestureDetector(
                      onTap: () =>
                          showProfilePicturePreview(context, avatarProvider),
                      child: CircleAvatar(
                        key: ValueKey(_imageRefreshKey),
                        radius: context.sw(50),
                        backgroundColor: AppColors.cyan,
                        backgroundImage: avatarProvider,
                        child: null,
                      ),
                    ),
                  ),
                  SizedBox(height: context.sh(16)),
                  Center(
                    child: Text(
                      userName,
                      style: TextStyle(
                          fontSize: context.sp(22),
                          fontWeight: FontWeight.bold,
                          color: AppThemeColors.primaryText(context)),
                    ),
                  ),
                  SizedBox(height: context.sh(22)),
                  if (userName.isNotEmpty)
                    _profileField(Icons.person, t('name'), userName),
                  if (username.isNotEmpty)
                    _profileField(
                        Icons.account_circle, t('username'), username),
                  if (email.isNotEmpty)
                    _profileField(Icons.email, t('email'), email),
                  if (altEmail.isNotEmpty)
                    _profileField(
                        Icons.alternate_email, t('alternate_email'), altEmail),
                  if (gender.isNotEmpty)
                    _profileField(Icons.transgender, t('gender'), gender),
                  if (birthday.isNotEmpty)
                    _profileField(Icons.cake, t('birthday'), birthdayDisplay),
                  if (address.isNotEmpty)
                    _profileField(Icons.home, t('address'), address),
                  if (phone.isNotEmpty)
                    _profileField(Icons.phone, t('phone'), phone),
                  if (memberSince.isNotEmpty)
                    _profileField(Icons.calendar_today, t('member_since'),
                        memberSinceDisplay),
                  if (avgRating.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                            child: _profileField(
                                Icons.star, t('avg_rating'), avgRating)),
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
                  if (user?['trustScore'] is Map)
                    _trustScoreBadge(
                        Map<String, dynamic>.from(user!['trustScore'])),
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
                      child: Text(t('edit_profile'),
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
                      child: Text(t('settings'),
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
          color: AppThemeColors.cardBg(context),
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
                            fontSize: context.sp(15),
                            color: AppThemeColors.primaryText(context)),
                      ),
                      TextSpan(
                        text: value,
                        style: TextStyle(
                            fontSize: context.sp(15),
                            fontWeight: FontWeight.normal,
                            color: AppThemeColors.primaryText(context)),
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

  Widget _trustScoreBadge(Map<String, dynamic> trustScore) {
    final t = AppLocalizations.of(context).t;
    final score = trustScore['score'] as int?;
    final label = (trustScore['label'] ?? '').toString();
    final resolvedCount = trustScore['resolvedCount'] as int? ?? 0;

    Color color;
    String translatedLabel;
    switch (label) {
      case 'Excellent':
        color = const Color(0xFF2E7D32);
        translatedLabel = t('excellent');
        break;
      case 'Good':
        color = AppColors.cyan;
        translatedLabel = t('good');
        break;
      case 'Fair':
        color = const Color(0xFFFF9933);
        translatedLabel = t('fair');
        break;
      case 'Poor':
        color = const Color(0xFFD32F2F);
        translatedLabel = t('poor');
        break;
      default:
        color = Colors.grey;
        translatedLabel = label;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  score != null
                      ? '${t('repayment_reliability_label')}: $score% ($translatedLabel)'
                      : '${t('repayment_reliability_label')}: $translatedLabel',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: context.sp(15),
                      color: color),
                ),
                if (score != null)
                  Text(
                    '${t('based_on_label')} $resolvedCount ${resolvedCount == 1 ? t('resolved_transaction_singular') : t('resolved_transactions_plural')}',
                    style: TextStyle(
                        fontSize: context.sp(12),
                        color: AppThemeColors.secondaryText(context)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


