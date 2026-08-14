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
import '../widgets/app_widgets.dart';
import '../widgets/wave_widget.dart' show DeepTopWaveClipper;
import '../widgets/avatar_action_sheet.dart';
import '../widgets/birthday_banner.dart';


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
  int _imageRefreshKey = 0;
  ImageProvider? _cachedAvatarImage;
  int _lastAvatarKey = -1;
  bool _statsLoading = true;
  double _totalLent = 0;
  double _totalBorrowed = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchProfile());
  }

  Future<void> _fetchProfile() async {
    setState(() { _loading = true; _error = null; });
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (widget.email != null && widget.email!.isNotEmpty) {
      // Fetch profile by email (admin viewing another user)
      final path =
          '/api/users/profile-by-email?email=${Uri.encodeComponent(widget.email!)}';
      try {
        final response = await ApiClient.get(path);
        if (!mounted) return;
        if (response.statusCode == 200) {
          setState(() {
            _profile = jsonDecode(response.body);
            _loading = false;
            _error = null;
            _imageRefreshKey++;
          });
        } else {
          setState(() {
            _error = AppLocalizations.of(context).t('user_not_found');
            _loading = false;
          });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = AppLocalizations.of(context).t('error_loading_profile');
          _loading = false;
        });
      }
      return;
    }

    if (session.accessToken == null) {
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
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _profile = jsonDecode(response.body);
          _loading = false;
          _error = null;
          _imageRefreshKey++; // Force avatar rebuild
        });
        _fetchStats();
      } else {
        setState(() {
          _error = AppLocalizations.of(context).t('error_loading_profile');
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).t('error_loading_profile');
        _loading = false;
      });
    }
  }

  Future<void> _fetchStats() async {
    try {
      final response = await ApiClient.get('/api/analytics/quick');
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _totalLent = (data['totalLent'] is num)
              ? (data['totalLent'] as num).toDouble()
              : double.tryParse(data['totalLent']?.toString() ?? '') ?? 0.0;
          _totalBorrowed = (data['totalBorrowed'] is num)
              ? (data['totalBorrowed'] as num).toDouble()
              : double.tryParse(data['totalBorrowed']?.toString() ?? '') ?? 0.0;
          _statsLoading = false;
        });
      } else {
        if (mounted) setState(() => _statsLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _statsLoading = false);
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

    // Choose the correct avatar provider based on imageUrl. Cache per refresh
    // key so repeated builds don't generate a new URL (and re-download) each time.
    if (_imageRefreshKey != _lastAvatarKey || _cachedAvatarImage == null) {
      if (imageUrl != null &&
          imageUrl is String &&
          imageUrl.trim().isNotEmpty &&
          imageUrl != 'null') {
        _cachedAvatarImage = NetworkImage('$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      } else {
        _cachedAvatarImage = AssetImage(
          gender == 'Male'
              ? 'assets/Male.png'
              : gender == 'Female'
                  ? 'assets/Female.png'
                  : 'assets/Other.png',
        );
      }
      _lastAvatarKey = _imageRefreshKey;
    }
    final avatarProvider = _cachedAvatarImage!;
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
                    child: Column(children: [
                      Text(
                        userName,
                        style: TextStyle(
                            fontSize: context.sp(22),
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context)),
                      ),
                      if (username.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text('@$username',
                            style: TextStyle(
                                fontSize: context.sp(13),
                                color: AppThemeColors.secondaryText(context),
                                letterSpacing: 0.3)),
                      ],
                    ]),
                  ),
                  SizedBox(height: context.sh(20)),
                  _sectionCard(t('personal_information'), [
                    if (userName.isNotEmpty) _profileField(Icons.person, t('name'), userName),
                    if (username.isNotEmpty) _profileField(Icons.account_circle, t('username'), '@$username'),
                    if (gender.isNotEmpty) _profileField(Icons.transgender, t('gender'), gender),
                    if (birthday.isNotEmpty) _profileField(Icons.cake, t('birthday'), birthdayDisplay),
                  ]),
                  BirthdayBanner(birthdayRaw: birthday.isNotEmpty ? birthday : null),
                  _sectionCard(t('contact'), [
                    if (email.isNotEmpty) _profileField(Icons.email, t('email'), email),
                    if (altEmail.isNotEmpty) _profileField(Icons.alternate_email, t('alternate_email'), altEmail),
                  ]),
                  if (phone.isNotEmpty)
                    _buildPhoneDisplay(phone, user?['phoneCountryCode']?.toString() ?? '+91'),
                  _sectionCard(t('account_information'), [
                    if (address.isNotEmpty) _profileField(Icons.home, t('address'), address),
                    if (memberSince.isNotEmpty) _profileField(Icons.calendar_today, t('member_since'), memberSinceDisplay),
                    if (avgRating.isNotEmpty && (isViewingOwnProfile || session.hasFeature('view_rankings')))
                      _profileFieldWithTrailing(Icons.star, t('avg_rating'), avgRating,
                        Row(children: List.generate(5, (i) {
                          if (i < avgRatingNum.floor())
                            return Icon(Icons.star, color: const Color(0xFFFFC107), size: context.sp(18));
                          if (i == avgRatingNum.floor() && (avgRatingNum - avgRatingNum.floor()) >= 0.25)
                            return Icon(Icons.star_half, color: const Color(0xFFFFC107), size: context.sp(18));
                          return Icon(Icons.star_border, color: const Color(0xFFFFC107), size: context.sp(18));
                        })),
                    ),
                  ]),
                  _trustScoreBadge(
                    user?['trustScore'] is Map
                        ? Map<String, dynamic>.from(user!['trustScore'])
                        : const <String, dynamic>{},
                  ),
                  const SizedBox(height: 8),
                  _statsCard(user),
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
          if (_loading && user == null)
            const Center(child: CircularProgressIndicator()),
          if (_error != null && user == null)
            errorStateWidget(context, _error!, _fetchProfile),
        ],
      ),
    );
  }

  String _flagEmoji(String isoCode) => isoCode.toUpperCase().split('').map(
      (c) => String.fromCharCode(c.codeUnitAt(0) + 0x1F1A5)).join();

  Widget _buildPhoneDisplay(String phone, String countryCode) {
    const codeToMeta = {
      '+93': ('AF', 9),  '+355': ('AL', 9),  '+213': ('DZ', 9),
      '+54': ('AR', 10), '+374': ('AM', 8),  '+61': ('AU', 9),
      '+43': ('AT', 10), '+994': ('AZ', 9),  '+973': ('BH', 8),
      '+880': ('BD', 10),'+375': ('BY', 9),  '+32': ('BE', 9),
      '+591': ('BO', 8), '+387': ('BA', 8),  '+55': ('BR', 11),
      '+1': ('US', 10),  '+56': ('CL', 9),   '+86': ('CN', 11),
      '+57': ('CO', 10), '+385': ('HR', 9),  '+53': ('CU', 8),
      '+420': ('CZ', 9), '+45': ('DK', 8),   '+593': ('EC', 9),
      '+20': ('EG', 10), '+251': ('ET', 9),  '+358': ('FI', 9),
      '+33': ('FR', 9),  '+995': ('GE', 9),  '+49': ('DE', 11),
      '+233': ('GH', 9), '+30': ('GR', 10),  '+502': ('GT', 8),
      '+36': ('HU', 9),  '+91': ('IN', 10),  '+62': ('ID', 11),
      '+98': ('IR', 10), '+964': ('IQ', 10), '+353': ('IE', 9),
      '+972': ('IL', 9), '+39': ('IT', 10),  '+81': ('JP', 10),
      '+962': ('JO', 9), '+77': ('KZ', 10),  '+254': ('KE', 9),
      '+965': ('KW', 8), '+961': ('LB', 8),  '+218': ('LY', 9),
      '+60': ('MY', 9),  '+52': ('MX', 10),  '+212': ('MA', 9),
      '+95': ('MM', 9),  '+977': ('NP', 10), '+31': ('NL', 9),
      '+64': ('NZ', 9),  '+234': ('NG', 10), '+47': ('NO', 8),
      '+968': ('OM', 8), '+92': ('PK', 10),  '+595': ('PY', 9),
      '+51': ('PE', 9),  '+63': ('PH', 10),  '+48': ('PL', 9),
      '+351': ('PT', 9), '+974': ('QA', 8),  '+40': ('RO', 9),
      '+7': ('RU', 10),  '+966': ('SA', 9),  '+221': ('SN', 9),
      '+381': ('RS', 9), '+65': ('SG', 8),   '+27': ('ZA', 9),
      '+82': ('KR', 10), '+34': ('ES', 9),   '+94': ('LK', 9),
      '+249': ('SD', 9), '+46': ('SE', 9),   '+41': ('CH', 9),
      '+963': ('SY', 9), '+886': ('TW', 9),  '+255': ('TZ', 9),
      '+66': ('TH', 9),  '+216': ('TN', 8),  '+90': ('TR', 10),
      '+256': ('UG', 9), '+380': ('UA', 9),  '+971': ('AE', 9),
      '+44': ('GB', 10), '+598': ('UY', 9),  '+998': ('UZ', 9),
      '+58': ('VE', 10), '+84': ('VN', 9),   '+967': ('YE', 9),
      '+260': ('ZM', 9), '+263': ('ZW', 9),
    };
    final meta = codeToMeta[countryCode] ?? ('IN', 10);
    final isoCode = meta.$1;
    final digitCount = meta.$2;
    final flag = _flagEmoji(isoCode);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: AppColors.tricolorGradient,
      ),
      padding: const EdgeInsets.all(2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: AppThemeColors.cardBg(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.phone, color: AppColors.cyan),
                const SizedBox(width: 10),
                Text('Phone', style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: context.sp(13),
                  color: AppThemeColors.primaryText(context),
                )),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
                  ),
                  child: Text('$flag $countryCode',
                    style: TextStyle(fontSize: context.sp(12), color: AppColors.cyan, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(digitCount, (i) {
                    final d = i < phone.length ? phone[i] : '';
                    return Container(
                      width: 30,
                      height: 36,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: d.isNotEmpty
                            ? AppColors.cyan.withValues(alpha: 0.1)
                            : AppThemeColors.divider(context).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: d.isNotEmpty ? AppColors.cyan.withValues(alpha: 0.5) : AppThemeColors.divider(context),
                        ),
                      ),
                      child: Center(
                        child: Text(d, style: TextStyle(
                          fontSize: context.sp(15),
                          fontWeight: FontWeight.bold,
                          color: AppThemeColors.primaryText(context),
                        )),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(String title, List<Widget> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppThemeColors.border(context).withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
          child: Row(children: [
            Container(width: 3, height: 13,
                decoration: BoxDecoration(color: AppColors.cyan,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text(title.toUpperCase(),
                style: TextStyle(fontSize: context.sp(10), fontWeight: FontWeight.bold,
                    color: AppColors.cyan, letterSpacing: 1.0)),
          ]),
        ),
        Divider(height: 1, color: AppThemeColors.border(context).withValues(alpha: 0.4)),
        ...rows.asMap().entries.map((e) => Column(children: [
          if (e.key > 0) Divider(height: 1, indent: 66,
              color: AppThemeColors.border(context).withValues(alpha: 0.3)),
          e.value,
        ])),
        const SizedBox(height: 4),
      ]),
    );
  }

  Widget _profileField(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppColors.cyan, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: context.sp(11),
              color: AppThemeColors.secondaryText(context), letterSpacing: 0.2)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: context.sp(15),
              fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context))),
        ])),
      ]),
    );
  }

  Widget _profileFieldWithTrailing(IconData icon, String label, String value, Widget trailing) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppColors.cyan, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: context.sp(11),
              color: AppThemeColors.secondaryText(context), letterSpacing: 0.2)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: context.sp(15),
              fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context))),
        ])),
        trailing,
      ]),
    );
  }

  Widget _statItem(BuildContext ctx, String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.cyan, size: ctx.sp(22)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: ctx.sp(18),
            fontWeight: FontWeight.bold,
            color: AppThemeColors.primaryText(ctx),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: ctx.sp(11),
            color: AppThemeColors.secondaryText(ctx),
          ),
        ),
      ],
    );
  }

  Widget _verticalDivider() {
    return SizedBox(
      height: 48,
      child: VerticalDivider(
        color: AppThemeColors.border(context).withValues(alpha: 0.5),
        thickness: 1,
        width: 1,
      ),
    );
  }

  Widget _statsCard(Map<String, dynamic>? user) {
    final friendCount = user?['friendCount'] ?? 0;
    final quickCount = user?['quickTransactionCount'] ?? 0;
    final secureCount = user?['secureTransactionCount'] ?? 0;

    final netLent = _totalLent - _totalBorrowed;
    final isNetLent = netLent >= 0;
    final netColor = isNetLent ? const Color(0xFF2E7D32) : AppColors.tricolorOrange;
    final netLabel = isNetLent ? 'Net Lent' : 'Net Borrowed';
    final netValue = _statsLoading
        ? '--'
        : '₹${netLent.abs().toStringAsFixed(0)}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppThemeColors.border(context).withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
            child: Row(children: [
              Container(
                width: 3,
                height: 13,
                decoration: BoxDecoration(
                  color: AppColors.cyan,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ACTIVITY',
                style: TextStyle(
                  fontSize: context.sp(10),
                  fontWeight: FontWeight.bold,
                  color: AppColors.cyan,
                  letterSpacing: 1.0,
                ),
              ),
            ]),
          ),
          Divider(
            height: 1,
            color: AppThemeColors.border(context).withValues(alpha: 0.4),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem(context, 'Friends', '$friendCount', Icons.people_rounded),
                _verticalDivider(),
                _statItem(context, 'Quick Txns', '$quickCount', Icons.flash_on_rounded),
                _verticalDivider(),
                _statItem(context, 'Secure Txns', '$secureCount', Icons.security_rounded),
              ],
            ),
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: AppThemeColors.border(context).withValues(alpha: 0.3),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  isNetLent ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  color: netColor,
                  size: context.sp(18),
                ),
                const SizedBox(width: 8),
                Text(
                  netLabel,
                  style: TextStyle(
                    fontSize: context.sp(13),
                    color: AppThemeColors.secondaryText(context),
                  ),
                ),
                const Spacer(),
                Text(
                  netValue,
                  style: TextStyle(
                    fontSize: context.sp(16),
                    fontWeight: FontWeight.bold,
                    color: netColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _trustScoreBadge(Map<String, dynamic> trustScore) {
    final t = AppLocalizations.of(context).t;
    final score = trustScore['score'] as int?;
    final resolvedCount = trustScore['resolvedCount'] as int? ?? 0;
    // Three distinct states:
    // 1. score != null  → has enough resolved history, show actual score
    // 2. score == null && resolvedCount > 0 → building (some history, not enough yet)
    // 3. resolvedCount == 0  → brand new user
    final bool hasScore = score != null;
    final bool hasAnyHistory = resolvedCount > 0;

    Color color;
    String strengthLabel;
    String bottomLabel;

    if (hasScore) {
      if (score >= 90) {
        color = const Color(0xFF2E7D32);
        strengthLabel = 'Excellent';
      } else if (score >= 75) {
        color = const Color(0xFF00897B);
        strengthLabel = 'Strong';
      } else if (score >= 55) {
        color = AppColors.cyan;
        strengthLabel = 'Good';
      } else if (score >= 35) {
        color = AppColors.tricolorOrange;
        strengthLabel = 'Fair';
      } else {
        color = const Color(0xFFD32F2F);
        strengthLabel = 'Weak';
      }
      bottomLabel = '${t('based_on_label')} $resolvedCount ${resolvedCount == 1 ? t('resolved_transaction_singular') : t('resolved_transactions_plural')}';
    } else if (hasAnyHistory) {
      color = const Color(0xFF5C6BC0); // indigo — building state
      strengthLabel = 'Building';
      bottomLabel = '$resolvedCount resolved so far — keep transacting';
    } else {
      color = Colors.grey;
      strengthLabel = 'New User';
      bottomLabel = 'No transaction history yet';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t('repayment_reliability_label'),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: context.sp(13),
                    color: AppThemeColors.secondaryText(context),
                  ),
                ),
              ),
              Text(
                hasScore ? '$score%' : (hasAnyHistory ? '...' : '--'),
                style: TextStyle(
                  fontSize: context.sp(22),
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: hasScore ? (score / 100) : (hasAnyHistory ? 0.15 : 0.0),
              backgroundColor: AppThemeColors.border(context).withValues(alpha: 0.25),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 7,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  strengthLabel,
                  style: TextStyle(
                    fontSize: context.sp(11),
                    fontWeight: FontWeight.bold,
                    color: color,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  bottomLabel,
                  style: TextStyle(
                    fontSize: context.sp(11),
                    color: AppThemeColors.secondaryText(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


