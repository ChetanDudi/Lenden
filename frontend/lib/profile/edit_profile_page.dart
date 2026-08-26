import 'package:flutter/material.dart';
import '../utils/pickers.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import '../utils/image_picker_utils.dart';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import '../utils/http_interceptor.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../widgets/wave_widget.dart';
import '../utils/theme_helper.dart';
import '../utils/responsive.dart';
import '../l10n/app_localizations.dart';
import '../widgets/avatar_action_sheet.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _birthdayController;
  late TextEditingController _emailController;
  String _phoneCountryCode = '+91';
  String _phoneCountryIso = 'IN';
  int _phoneDigitCount = 10;
  String? _phoneError;
  final List<TextEditingController> _phoneControllers = List.generate(10, (_) => TextEditingController());
  final List<FocusNode> _phoneFocusNodes = List.generate(10, (_) => FocusNode());
  late TextEditingController _passwordController;
  late TextEditingController _addressController;
  String? _gender;
  Uint8List? _newImageBytes;
  String? _newImageMime;
  bool _removeImage = false;
  int _imageRefreshKey = 0;
  ImageProvider? _cachedNetworkAvatar;
  int _lastAvatarKey = -1;
  bool _isUpdating = false;

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
    _emailController = TextEditingController(text: user?['email'] ?? '');
    // Initialise 10-box phone controllers from stored number
    final existingPhone = (user?['phone'] ?? '').toString();
    for (int i = 0; i < 10; i++) {
      _phoneControllers[i].text = i < existingPhone.length ? existingPhone[i] : '';
    }
    _phoneCountryCode = (user?['phoneCountryCode'] ?? '+91').toString();
    _phoneCountryIso = _isoForCode(_phoneCountryCode);
    _phoneDigitCount = _digitCountForCode(_phoneCountryCode);
    _passwordController = TextEditingController();
    _addressController = TextEditingController(text: user?['address'] ?? '');
    _gender = user?['gender'] ?? 'Other'; // raw backend value, not display text
  }

  @override
  void dispose() {
    _nameController.dispose();
    _birthdayController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _addressController.dispose();
    for (final c in _phoneControllers) c.dispose();
    for (final f in _phoneFocusNodes) f.dispose();
    super.dispose();
  }

  // ── Phone helpers ────────────────────────────────────────────────────────

  static const _countries = [
    {'name': 'Afghanistan',          'code': '+93',  'iso': 'AF', 'digits': '9'},
    {'name': 'Albania',              'code': '+355', 'iso': 'AL', 'digits': '9'},
    {'name': 'Algeria',              'code': '+213', 'iso': 'DZ', 'digits': '9'},
    {'name': 'Argentina',            'code': '+54',  'iso': 'AR', 'digits': '10'},
    {'name': 'Armenia',              'code': '+374', 'iso': 'AM', 'digits': '8'},
    {'name': 'Australia',            'code': '+61',  'iso': 'AU', 'digits': '9'},
    {'name': 'Austria',              'code': '+43',  'iso': 'AT', 'digits': '10'},
    {'name': 'Azerbaijan',           'code': '+994', 'iso': 'AZ', 'digits': '9'},
    {'name': 'Bahrain',              'code': '+973', 'iso': 'BH', 'digits': '8'},
    {'name': 'Bangladesh',           'code': '+880', 'iso': 'BD', 'digits': '10'},
    {'name': 'Belarus',              'code': '+375', 'iso': 'BY', 'digits': '9'},
    {'name': 'Belgium',              'code': '+32',  'iso': 'BE', 'digits': '9'},
    {'name': 'Bolivia',              'code': '+591', 'iso': 'BO', 'digits': '8'},
    {'name': 'Bosnia & Herzegovina', 'code': '+387', 'iso': 'BA', 'digits': '8'},
    {'name': 'Brazil',               'code': '+55',  'iso': 'BR', 'digits': '11'},
    {'name': 'Canada',               'code': '+1',   'iso': 'CA', 'digits': '10'},
    {'name': 'Chile',                'code': '+56',  'iso': 'CL', 'digits': '9'},
    {'name': 'China',                'code': '+86',  'iso': 'CN', 'digits': '11'},
    {'name': 'Colombia',             'code': '+57',  'iso': 'CO', 'digits': '10'},
    {'name': 'Croatia',              'code': '+385', 'iso': 'HR', 'digits': '9'},
    {'name': 'Cuba',                 'code': '+53',  'iso': 'CU', 'digits': '8'},
    {'name': 'Czech Republic',       'code': '+420', 'iso': 'CZ', 'digits': '9'},
    {'name': 'Denmark',              'code': '+45',  'iso': 'DK', 'digits': '8'},
    {'name': 'Ecuador',              'code': '+593', 'iso': 'EC', 'digits': '9'},
    {'name': 'Egypt',                'code': '+20',  'iso': 'EG', 'digits': '10'},
    {'name': 'Ethiopia',             'code': '+251', 'iso': 'ET', 'digits': '9'},
    {'name': 'Finland',              'code': '+358', 'iso': 'FI', 'digits': '9'},
    {'name': 'France',               'code': '+33',  'iso': 'FR', 'digits': '9'},
    {'name': 'Georgia',              'code': '+995', 'iso': 'GE', 'digits': '9'},
    {'name': 'Germany',              'code': '+49',  'iso': 'DE', 'digits': '11'},
    {'name': 'Ghana',                'code': '+233', 'iso': 'GH', 'digits': '9'},
    {'name': 'Greece',               'code': '+30',  'iso': 'GR', 'digits': '10'},
    {'name': 'Guatemala',            'code': '+502', 'iso': 'GT', 'digits': '8'},
    {'name': 'Hungary',              'code': '+36',  'iso': 'HU', 'digits': '9'},
    {'name': 'India',                'code': '+91',  'iso': 'IN', 'digits': '10'},
    {'name': 'Indonesia',            'code': '+62',  'iso': 'ID', 'digits': '11'},
    {'name': 'Iran',                 'code': '+98',  'iso': 'IR', 'digits': '10'},
    {'name': 'Iraq',                 'code': '+964', 'iso': 'IQ', 'digits': '10'},
    {'name': 'Ireland',              'code': '+353', 'iso': 'IE', 'digits': '9'},
    {'name': 'Israel',               'code': '+972', 'iso': 'IL', 'digits': '9'},
    {'name': 'Italy',                'code': '+39',  'iso': 'IT', 'digits': '10'},
    {'name': 'Japan',                'code': '+81',  'iso': 'JP', 'digits': '10'},
    {'name': 'Jordan',               'code': '+962', 'iso': 'JO', 'digits': '9'},
    {'name': 'Kazakhstan',           'code': '+77',  'iso': 'KZ', 'digits': '10'},
    {'name': 'Kenya',                'code': '+254', 'iso': 'KE', 'digits': '9'},
    {'name': 'Kuwait',               'code': '+965', 'iso': 'KW', 'digits': '8'},
    {'name': 'Lebanon',              'code': '+961', 'iso': 'LB', 'digits': '8'},
    {'name': 'Libya',                'code': '+218', 'iso': 'LY', 'digits': '9'},
    {'name': 'Malaysia',             'code': '+60',  'iso': 'MY', 'digits': '9'},
    {'name': 'Mexico',               'code': '+52',  'iso': 'MX', 'digits': '10'},
    {'name': 'Morocco',              'code': '+212', 'iso': 'MA', 'digits': '9'},
    {'name': 'Myanmar',              'code': '+95',  'iso': 'MM', 'digits': '9'},
    {'name': 'Nepal',                'code': '+977', 'iso': 'NP', 'digits': '10'},
    {'name': 'Netherlands',          'code': '+31',  'iso': 'NL', 'digits': '9'},
    {'name': 'New Zealand',          'code': '+64',  'iso': 'NZ', 'digits': '9'},
    {'name': 'Nigeria',              'code': '+234', 'iso': 'NG', 'digits': '10'},
    {'name': 'Norway',               'code': '+47',  'iso': 'NO', 'digits': '8'},
    {'name': 'Oman',                 'code': '+968', 'iso': 'OM', 'digits': '8'},
    {'name': 'Pakistan',             'code': '+92',  'iso': 'PK', 'digits': '10'},
    {'name': 'Paraguay',             'code': '+595', 'iso': 'PY', 'digits': '9'},
    {'name': 'Peru',                 'code': '+51',  'iso': 'PE', 'digits': '9'},
    {'name': 'Philippines',          'code': '+63',  'iso': 'PH', 'digits': '10'},
    {'name': 'Poland',               'code': '+48',  'iso': 'PL', 'digits': '9'},
    {'name': 'Portugal',             'code': '+351', 'iso': 'PT', 'digits': '9'},
    {'name': 'Qatar',                'code': '+974', 'iso': 'QA', 'digits': '8'},
    {'name': 'Romania',              'code': '+40',  'iso': 'RO', 'digits': '9'},
    {'name': 'Russia',               'code': '+7',   'iso': 'RU', 'digits': '10'},
    {'name': 'Saudi Arabia',         'code': '+966', 'iso': 'SA', 'digits': '9'},
    {'name': 'Senegal',              'code': '+221', 'iso': 'SN', 'digits': '9'},
    {'name': 'Serbia',               'code': '+381', 'iso': 'RS', 'digits': '9'},
    {'name': 'Singapore',            'code': '+65',  'iso': 'SG', 'digits': '8'},
    {'name': 'South Africa',         'code': '+27',  'iso': 'ZA', 'digits': '9'},
    {'name': 'South Korea',          'code': '+82',  'iso': 'KR', 'digits': '10'},
    {'name': 'Spain',                'code': '+34',  'iso': 'ES', 'digits': '9'},
    {'name': 'Sri Lanka',            'code': '+94',  'iso': 'LK', 'digits': '9'},
    {'name': 'Sudan',                'code': '+249', 'iso': 'SD', 'digits': '9'},
    {'name': 'Sweden',               'code': '+46',  'iso': 'SE', 'digits': '9'},
    {'name': 'Switzerland',          'code': '+41',  'iso': 'CH', 'digits': '9'},
    {'name': 'Syria',                'code': '+963', 'iso': 'SY', 'digits': '9'},
    {'name': 'Taiwan',               'code': '+886', 'iso': 'TW', 'digits': '9'},
    {'name': 'Tanzania',             'code': '+255', 'iso': 'TZ', 'digits': '9'},
    {'name': 'Thailand',             'code': '+66',  'iso': 'TH', 'digits': '9'},
    {'name': 'Tunisia',              'code': '+216', 'iso': 'TN', 'digits': '8'},
    {'name': 'Turkey',               'code': '+90',  'iso': 'TR', 'digits': '10'},
    {'name': 'Uganda',               'code': '+256', 'iso': 'UG', 'digits': '9'},
    {'name': 'Ukraine',              'code': '+380', 'iso': 'UA', 'digits': '9'},
    {'name': 'United Arab Emirates', 'code': '+971', 'iso': 'AE', 'digits': '9'},
    {'name': 'United Kingdom',       'code': '+44',  'iso': 'GB', 'digits': '10'},
    {'name': 'United States',        'code': '+1',   'iso': 'US', 'digits': '10'},
    {'name': 'Uruguay',              'code': '+598', 'iso': 'UY', 'digits': '9'},
    {'name': 'Uzbekistan',           'code': '+998', 'iso': 'UZ', 'digits': '9'},
    {'name': 'Venezuela',            'code': '+58',  'iso': 'VE', 'digits': '10'},
    {'name': 'Vietnam',              'code': '+84',  'iso': 'VN', 'digits': '9'},
    {'name': 'Yemen',                'code': '+967', 'iso': 'YE', 'digits': '9'},
    {'name': 'Zambia',               'code': '+260', 'iso': 'ZM', 'digits': '9'},
    {'name': 'Zimbabwe',             'code': '+263', 'iso': 'ZW', 'digits': '9'},
  ];

  String _flagEmoji(String iso) => iso.toUpperCase().split('').map(
      (c) => String.fromCharCode(c.codeUnitAt(0) + 0x1F1A5)).join();

  String _isoForCode(String code) {
    final match = _countries.firstWhere(
        (c) => c['code'] == code, orElse: () => {'iso': 'IN'});
    return match['iso']!;
  }

  int _digitCountForCode(String code) {
    final match = _countries.firstWhere(
        (c) => c['code'] == code, orElse: () => {'digits': '10'});
    return int.tryParse(match['digits'] ?? '10') ?? 10;
  }

  String _phoneNumber() =>
      _phoneControllers.take(_phoneDigitCount).map((c) => c.text).join();

  bool _validatePhone() {
    final number = _phoneNumber();
    if (number.isEmpty) {
      setState(() => _phoneError = null);
      return true;
    }
    if (number.length != _phoneDigitCount) {
      setState(() => _phoneError =
          'Phone number must be exactly $_phoneDigitCount digits');
      return false;
    }
    setState(() => _phoneError = null);
    return true;
  }

  void _showCountryPicker() {
    final searchCtrl = TextEditingController();
    List<Map<String, String>> filtered = List.from(_countries);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeColors.cardBg(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, sc) => Column(children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search country…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (q) {
                  final lower = q.toLowerCase();
                  setS(() => filtered = _countries
                      .where((c) =>
                          c['name']!.toLowerCase().contains(lower) ||
                          c['code']!.contains(q))
                      .toList());
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.builder(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final c = filtered[i];
                  final flag = _flagEmoji(c['iso']!);
                  final selected = c['code'] == _phoneCountryCode;
                  return GestureDetector(
                    onTap: () {
                      final newCount = int.tryParse(c['digits'] ?? '10') ?? 10;
                      setState(() {
                        _phoneCountryCode = c['code']!;
                        _phoneCountryIso = c['iso']!;
                        _phoneDigitCount = newCount;
                        // Clear boxes beyond the new digit count
                        for (int j = newCount; j < _phoneControllers.length; j++) {
                          _phoneControllers[j].clear();
                        }
                        _phoneError = null;
                      });
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.cyan.withValues(alpha: 0.12)
                            : AppThemeColors.scaffoldBg(ctx),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? AppColors.cyan : AppThemeColors.divider(ctx),
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(flag, style: const TextStyle(fontSize: 26)),
                          const SizedBox(height: 2),
                          Text(
                            c['code']!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                              color: selected ? AppColors.cyan : AppThemeColors.primaryText(ctx),
                            ),
                          ),
                          Text(
                            '${c['digits']}d',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppThemeColors.mutedText(ctx),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildPhoneField() {
    final flag = _flagEmoji(_phoneCountryIso);
    return tricolorBorder(margin: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        color: AppThemeColors.cardBg(context),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.phone, color: AppColors.cyan),
              const SizedBox(width: 12),
              Text('Phone (optional)',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppThemeColors.mutedText(context))),
              const Spacer(),
              GestureDetector(
                onTap: _showCountryPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.cyan.withValues(alpha: 0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(flag, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(_phoneCountryCode,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.cyan)),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, color: AppColors.cyan, size: 18),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Text('$_phoneDigitCount digits required',
              style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_phoneDigitCount, (i) {
                return Container(
                  width: 30,
                  margin: const EdgeInsets.only(right: 5),
                  child: TextField(
                    controller: _phoneControllers[i],
                    focusNode: _phoneFocusNodes[i],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context)),
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppThemeColors.divider(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.cyan, width: 2),
                      ),
                    ),
                    onChanged: (val) {
                      if (val.isNotEmpty && i < 9) {
                        _phoneFocusNodes[i + 1].requestFocus();
                      } else if (val.isEmpty && i > 0) {
                        _phoneFocusNodes[i - 1].requestFocus();
                      }
                      _validatePhone();
                    },
                    onTap: () => _phoneControllers[i].selection =
                        TextSelection(baseOffset: 0, extentOffset: _phoneControllers[i].text.length),
                  ),
                );
              }),
              ),
            ),
            if (_phoneError != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.error_outline, size: 14, color: Colors.red),
                const SizedBox(width: 4),
                Text(_phoneError!,
                    style: const TextStyle(fontSize: 12, color: Colors.red)),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final result = await ImagePickerUtils.pickWithSheet(context);
      if (result == null || !mounted) return;
      setState(() {
        _newImageBytes = result.bytes;
        _newImageMime = 'image/jpeg';
        _removeImage = false;
        _imageRefreshKey++;
      });
    } catch (e) {
      if (!mounted) return;
      showSnack(context,
          '${AppLocalizations.of(context).t('error_picking_image_prefix')} $e',
          isError: true);
    }
  }

  Future<void> _removeProfileImage() async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppThemeColors.cardBg(ctx),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.no_photography_outlined, color: Colors.red, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                t('remove_photo_confirm_title'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                t('remove_photo_confirm_body'),
                style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(ctx), height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: AppThemeColors.divider(ctx)),
                    ),
                    child: Text(t('cancel'), style: TextStyle(color: AppThemeColors.secondaryText(ctx), fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text(t('remove'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) {
      setState(() {
        _newImageBytes = null;
        _removeImage = true;
        _imageRefreshKey++;
      });
    }
  }

  void _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final t = AppLocalizations.of(context).t;

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
      final phoneNumber = _phoneNumber();
      if (!_validatePhone()) {
        setState(() => _isUpdating = false);
        return;
      }
      request.fields['phone'] = phoneNumber;
      request.fields['phoneCountryCode'] = _phoneCountryCode;
      request.fields['address'] = _addressController.text;
      request.fields['gender'] = _gender ?? '';
      if (_removeImage) {
        request.fields['removeImage'] = 'true';
      } else if (_newImageBytes != null) {
        final mime = (_newImageMime ?? 'image/jpeg').split('/');
        request.files.add(http.MultipartFile.fromBytes(
            'profileImage', _newImageBytes!,
            filename: 'profile.${mime.last}',
            contentType: MediaType(mime[0], mime[1])));
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

        showSnack(context, t('profile_updated_successfully'));
      } else {
        setState(() {
          _isUpdating = false;
        });
        showSnack(context, t('failed_to_update_profile'), isError: true);
      }
    } catch (e) {
      setState(() {
        _isUpdating = false;
      });
      showSnack(context, '${t('error_updating_profile_prefix')} $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final user = Provider.of<SessionProvider>(context).user;
    final gender = _gender ?? 'Other';
    final imageUrl = user?['profileImage'];

    Widget avatar;
    ImageProvider avatarProvider;
    if (_newImageBytes != null) {
      // Show newly selected image
      avatarProvider = MemoryImage(_newImageBytes!);
      avatar = CircleAvatar(
        key: ValueKey(_imageRefreshKey),
        radius: 54,
        backgroundImage: avatarProvider,
        backgroundColor: AppColors.cyan,
      );
    } else if (_removeImage ||
        imageUrl == null ||
        imageUrl.toString().isEmpty ||
        imageUrl == 'null') {
      // Show default avatar based on gender
      avatarProvider = AssetImage(
        gender == 'Male'
            ? 'assets/Male.png'
            : gender == 'Female'
                ? 'assets/Female.png'
                : 'assets/Other.png',
      );
      avatar = CircleAvatar(
        key: ValueKey(_imageRefreshKey),
        radius: 54,
        backgroundImage: avatarProvider,
        backgroundColor: AppColors.cyan,
      );
    }
    else {
      if (_imageRefreshKey != _lastAvatarKey || _cachedNetworkAvatar == null) {
        _cachedNetworkAvatar = NetworkImage('$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}');
        _lastAvatarKey = _imageRefreshKey;
      }
      avatarProvider = _cachedNetworkAvatar!;
      avatar = CircleAvatar(
        key: ValueKey(_imageRefreshKey),
        radius: 54,
        backgroundImage: avatarProvider,
        backgroundColor: AppColors.cyan,
        onBackgroundImageError: (exception, stackTrace) {},
      );
    }
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppThemeColors.primaryText(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(t('edit_profile_title'),
            style: TextStyle(color: AppThemeColors.primaryText(context), fontWeight: FontWeight.w700, fontSize: 18)),
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
              clipper: const CubicTopWaveClipper(),
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
                        child: GestureDetector(
                          onTap: () =>
                              showProfilePicturePreview(context, avatarProvider),
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
                            label: Text(t('upload'),
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
                            label: Text(t('remove'),
                                style: TextStyle(
                                    color: _isUpdating
                                        ? Colors.grey
                                        : Colors.red)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _sectionHeader(t('personal_information')),
                      _editField(Icons.person, t('name'), _nameController),
                      _editField(Icons.account_circle, t('username'),
                          TextEditingController(text: user?['username'] ?? ''),
                          readOnly: true),
                      _editGenderField(),
                      _editField(Icons.cake, t('birthday'), _birthdayController,
                          isBirthday: true),
                      Builder(builder: (bCtx) {
                        final bday = DateTime.tryParse(_birthdayController.text);
                        if (bday == null) return const SizedBox.shrink();
                        final now = DateTime.now();
                        if (bday.month != now.month || bday.day != now.day) return const SizedBox.shrink();
                        final age = now.year - bday.year;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF6B6B), Color(0xFFFFB300), Color(0xFF6BCB77)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.35), blurRadius: 12, spreadRadius: 1)],
                          ),
                          child: Row(children: [
                            const Text('🎂', style: TextStyle(fontSize: 26)),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Happy Birthday!', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                              Text(
                                age > 0 ? 'You\'re turning $age today 🎉' : 'Wishing you a wonderful day!',
                                style: const TextStyle(fontSize: 11, color: Colors.white70),
                              ),
                            ])),
                            const Icon(Icons.celebration_rounded, color: Colors.white70, size: 22),
                          ]),
                        );
                      }),
                      _sectionHeader(t('contact')),
                      _editField(Icons.email, t('email'), _emailController,
                          keyboardType: TextInputType.emailAddress,
                          readOnly: true),
                      _editField(Icons.alternate_email, t('alternate_email'),
                          TextEditingController(text: user?['altEmail'] ?? ''),
                          readOnly: true),
                      _buildPhoneField(),
                      _sectionHeader(t('account_information')),
                      _editField(Icons.home, t('address'), _addressController,
                          isOptional: true),
                      _editField(
                          Icons.calendar_today,
                          t('member_since'),
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
                                            t('avg_rating'),
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
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(t('saving_ellipsis'),
                                      style: TextStyle(
                                          fontSize: 18, color: Colors.white)),
                                ],
                              )
                            : Text(t('save'),
                                style: const TextStyle(
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
                        child: Text(t('cancel'),
                            style: TextStyle(
                                fontSize: 18,
                                color: AppThemeColors.primaryText(context))),
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
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
      child: Row(children: [
        Container(width: 3, height: 14,
            decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title.toUpperCase(),
            style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.bold,
                color: AppColors.cyan, letterSpacing: 1.0)),
      ]),
    );
  }

  Widget _editField(
      IconData icon, String label, TextEditingController controller,
      {TextInputType keyboardType = TextInputType.text,
      bool readOnly = false,
      bool isBirthday = false,
      bool isOptional = false}) {
    final t = AppLocalizations.of(context).t;
    final isDisabled = readOnly || isBirthday;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: isDisabled
            ? AppThemeColors.scaffoldBg(context)
            : AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDisabled
              ? AppThemeColors.border(context).withValues(alpha: 0.4)
              : AppThemeColors.border(context),
        ),
      ),
      child: Row(children: [
        const SizedBox(width: 14),
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: isDisabled
                ? AppThemeColors.border(context).withValues(alpha: 0.3)
                : AppColors.cyan.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: isDisabled ? AppThemeColors.secondaryText(context) : AppColors.cyan, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            readOnly: isDisabled,
            style: TextStyle(
              color: isDisabled
                  ? AppThemeColors.secondaryText(context)
                  : AppThemeColors.primaryText(context),
              fontSize: 15,
            ),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                color: isDisabled
                    ? AppThemeColors.secondaryText(context).withValues(alpha: 0.7)
                    : AppThemeColors.secondaryText(context),
                fontSize: 13,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              suffixIcon: isBirthday
                  ? IconButton(
                      icon: Icon(Icons.calendar_today, color: AppColors.cyan, size: 18),
                      onPressed: () async {
                        final picked = await showAppDatePicker(
                          context: context,
                          initialDate: controller.text.isNotEmpty
                              ? DateTime.tryParse(controller.text) ?? DateTime(2000)
                              : DateTime(2000),
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          controller.text = picked.toIso8601String().split('T').first;
                        }
                      },
                    )
                  : null,
            ),
            validator: (val) {
              if (readOnly || isBirthday || isOptional) return null;
              return val == null || val.isEmpty ? t('required') : null;
            },
          ),
        ),
        const SizedBox(width: 8),
      ]),
    );
  }

  Widget _editGenderField() {
    final t = AppLocalizations.of(context).t;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Row(children: [
        const SizedBox(width: 14),
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.transgender, color: AppColors.cyan, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _gender,
            style: TextStyle(color: AppThemeColors.primaryText(context), fontSize: 15),
            decoration: InputDecoration(
              labelText: t('gender'),
              labelStyle: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            items: [
              DropdownMenuItem(value: 'Male', child: Text(t('male'))),
              DropdownMenuItem(value: 'Female', child: Text(t('female'))),
              DropdownMenuItem(value: 'Other', child: Text(t('other'))),
            ],
            onChanged: (val) => setState(() => _gender = val),
            validator: (val) => val == null ? t('required') : null,
          ),
        ),
        const SizedBox(width: 8),
      ]),
    );
  }
}


