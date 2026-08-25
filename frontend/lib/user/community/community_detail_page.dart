import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../widgets/app_colors.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../utils/community_helpers.dart';
import '../../api_config.dart';
import '../../session.dart';
import '../../l10n/app_localizations.dart';
import 'package:share_plus/share_plus.dart';
import '../../utils/share_utils.dart';
import '../transaction/group_transactions/group_detail_page.dart';

class CommunityDetailPage extends StatefulWidget {
  final String communityId;
  final Map<String, dynamic>? initialData;

  const CommunityDetailPage({required this.communityId, this.initialData, super.key});

  @override
  State<CommunityDetailPage> createState() => _CommunityDetailPageState();
}

class _CommunityDetailPageState extends State<CommunityDetailPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic> _community = {};
  bool _loading = true;
  String? _error;
  double _totalBalance = 0;
  double _netBalance = 0;
  List<Map<String, dynamic>> _groupBalances = [];
  bool _loadingBalance = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    if (widget.initialData != null) _community = widget.initialData!;
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get('/api/communities/${widget.communityId}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) setState(() { _community = data['community']; _loading = false; });
        _loadBalance();
      } else {
        if (mounted) setState(() { _error = AppLocalizations.of(context).t('failed_to_load_community'); _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadBalance() async {
    setState(() => _loadingBalance = true);
    try {
      final res = await ApiClient.get('/api/communities/${widget.communityId}/balance');
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        if (mounted) setState(() {
          _totalBalance = (d['totalSplits'] ?? 0).toDouble();
          _netBalance = (d['netBalance'] ?? 0).toDouble();
          _groupBalances = List<Map<String, dynamic>>.from(d['groups'] ?? []);
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingBalance = false);
    }
  }

  Color _parseColor(dynamic c) {
    try {
      if (c is String && c.startsWith('#')) {
        return Color(int.parse('FF${c.replaceFirst('#', '')}', radix: 16));
      }
    } catch (_) {}
    return AppColors.cyan;
  }

  String get _uid => Provider.of<SessionProvider>(context, listen: false).user?['_id']?.toString() ?? '';

  bool get _isAdmin {
    final members = (_community['members'] as List?) ?? [];
    final me = members.firstWhere((m) => (m['user'] is Map ? (m['user'] as Map)['_id'] : m['user'])?.toString() == _uid, orElse: () => null);
    return me?['role']?.toString() == 'admin';
  }

  Color get _communityColor => _parseColor(_community['color']);
  String get _name => (_community['name'] ?? 'Community').toString();
  String get _inviteCode => (_community['inviteCode'] ?? '').toString();
  List get _members => (_community['members'] as List?) ?? [];
  List get _groups => (_community['groups'] as List?) ?? [];

  void _showSnack(String msg, {bool isError = false, IconData? icon}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(icon ?? (isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded), color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: isError ? Colors.red.shade700 : AppColors.cyan,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
    ));
  }

  Future<void> _addGroupToCommunity() async {
    // Load user's groups that are not already in this community
    List<Map<String, dynamic>> available = [];
    try {
      final res = await ApiClient.get('/api/group-transactions/user-groups');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final allGroups = List<Map<String, dynamic>>.from(data['groups'] ?? []);
        final communityGroupIds = _groups.map((g) => (g['_id'] ?? g).toString()).toSet();
        available = allGroups.where((g) => !communityGroupIds.contains((g['_id'] ?? '').toString())).toList();
      }
    } catch (_) {}

    if (!mounted) return;
    if (available.isEmpty) {
      _showSnack(AppLocalizations.of(context).t('no_available_groups_snack'), icon: Icons.info_outline_rounded);
      return;
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            Container(width: 40, height: 40,
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 20)),
            const SizedBox(width: 12),
            Text(AppLocalizations.of(ctx).t('add_group_to_community_title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
          ]),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.45),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: available.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final g = available[i];
                final gId = (g['_id'] ?? '').toString();
                final gName = (g['title'] ?? '').toString();
                final gColor = _parseColor(g['color']);
                return GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      final r = await ApiClient.post('/api/communities/${widget.communityId}/groups', body: {'groupId': gId});
                      if (r.statusCode == 200) { _load(); _showSnack(AppLocalizations.of(context).t('group_added_community_snack'), icon: Icons.check_rounded); }
                      else { _showSnack(jsonDecode(r.body)['error'] ?? 'Failed', isError: true); }
                    } catch (e) { _showSnack(e.toString(), isError: true); }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppThemeColors.surfaceBg(ctx),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: gColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Container(width: 38, height: 38,
                        decoration: BoxDecoration(color: gColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                        child: Center(child: Text(gName.isNotEmpty ? gName[0].toUpperCase() : 'G',
                          style: TextStyle(color: gColor, fontWeight: FontWeight.bold, fontSize: 16)))),
                      const SizedBox(width: 12),
                      Expanded(child: Text(gName, style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(ctx)))),
                      Icon(Icons.add_circle_outline_rounded, color: AppColors.cyan, size: 20),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  static const _presetColors = [
    Color(0xFF00B4D8), Color(0xFF0096C7), Color(0xFF023E8A), Color(0xFF2196F3),
    Color(0xFF3F51B5), Color(0xFF673AB7), Color(0xFF9C27B0), Color(0xFFE91E63),
    Color(0xFFF44336), Color(0xFFFF5722), Color(0xFFFF9800), Color(0xFFFFC107),
    Color(0xFF4CAF50), Color(0xFF009688), Color(0xFF8BC34A), Color(0xFF607D8B),
  ];

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 512, maxHeight: 512);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    try {
      final res = await ApiClient.postMultipart(
        '/api/communities/${widget.communityId}/image',
        files: [ApiMultipartFile(field: 'image', filename: picked.name, bytes: bytes)],
      );
      if (res.statusCode == 200) {
        _load();
        _showSnack(AppLocalizations.of(context).t('photo_updated_snack'), icon: Icons.check_rounded);
      } else {
        _showSnack(jsonDecode(res.body)['error'] ?? 'Upload failed', isError: true);
      }
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  void _showEditCommunity() {
    final nameCtrl = TextEditingController(text: _name);
    final descCtrl = TextEditingController(text: (_community['description'] ?? '').toString());
    Color tempColor = _communityColor;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(ctx),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.edit_rounded, color: Color(0xFF8B5CF6), size: 20)),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(ctx).t('edit_community_label'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(ctx))),
              ]),
              const SizedBox(height: 20),

              // Name field
              Container(
                decoration: BoxDecoration(
                  color: AppThemeColors.surfaceBg(ctx),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppThemeColors.border(ctx)),
                ),
                child: TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: AppThemeColors.primaryText(ctx), fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(ctx).t('community_name_label'),
                    labelStyle: TextStyle(color: AppThemeColors.secondaryText(ctx), fontSize: 13),
                    prefixIcon: Icon(Icons.hub_rounded, color: AppThemeColors.secondaryText(ctx), size: 18),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Description field
              Container(
                decoration: BoxDecoration(
                  color: AppThemeColors.surfaceBg(ctx),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppThemeColors.border(ctx)),
                ),
                child: TextField(
                  controller: descCtrl,
                  minLines: 2, maxLines: 3,
                  style: TextStyle(color: AppThemeColors.primaryText(ctx)),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(ctx).t('description_optional_label'),
                    labelStyle: TextStyle(color: AppThemeColors.secondaryText(ctx), fontSize: 13),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Icon(Icons.notes_rounded, color: AppThemeColors.secondaryText(ctx), size: 18),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Color picker
              Row(children: [
                Text(AppLocalizations.of(ctx).t('color_picker_label'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: AppThemeColors.secondaryText(ctx))),
                const SizedBox(width: 10),
                Container(width: 22, height: 22, decoration: BoxDecoration(color: tempColor, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: tempColor.withValues(alpha: 0.4), blurRadius: 6)])),
              ]),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8, crossAxisSpacing: 10, mainAxisSpacing: 10),
                itemCount: _presetColors.length,
                itemBuilder: (_, i) {
                  final c = _presetColors[i];
                  final sel = tempColor.toARGB32() == c.toARGB32();
                  return GestureDetector(
                    onTap: () => setSheet(() => tempColor = c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: sel ? Colors.white : Colors.transparent, width: 2),
                        boxShadow: sel ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 8)] : [],
                      ),
                      child: sel ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) : null,
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // Save button
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [tempColor, Color.lerp(tempColor, Colors.black, 0.2)!]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: tempColor.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                    minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
                  onPressed: saving ? null : () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    setSheet(() => saving = true);
                    final hexColor = '#${tempColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
                    try {
                      final res = await ApiClient.patch(
                        '/api/communities/${widget.communityId}',
                        body: {'name': name, 'description': descCtrl.text.trim(), 'color': hexColor},
                      );
                      if (res.statusCode == 200) {
                        Navigator.pop(ctx);
                        _load();
                        _showSnack(AppLocalizations.of(context).t('community_updated_snack'), icon: Icons.check_rounded);
                      } else {
                        _showSnack(jsonDecode(res.body)['error'] ?? 'Failed', isError: true);
                      }
                    } catch (e) {
                      _showSnack(e.toString(), isError: true);
                    }
                    setSheet(() => saving = false);
                  },
                  child: saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(AppLocalizations.of(ctx).t('save_changes_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _showShareSheet() async {
    final appLink = await fetchAppInviteLink();
    final referralCode = await fetchReferralCode();
    if (!mounted) return;

    final memberCount = _members.length;
    final groupCount = _groups.length;
    final downloadLine = appLink.isNotEmpty ? '\n📥 Download LenDen: $appLink' : '';
    final referralLine = referralCode.isNotEmpty
        ? '\n🎁 *Referral Code: $referralCode*\n'
          '   (New to LenDen? Enter this code on sign-up to earn bonus coins!)'
        : '';
    final msg = '🏘️ You\'re invited to join *$_name* on LenDen!\n\n'
        '👥 Community: $_name\n'
        '${_community['description']?.toString().isNotEmpty == true ? '📝 ${_community['description']}\n' : ''}'
        '👤 Members: $memberCount   📁 Groups: $groupCount\n\n'
        '🔑 Community Invite Code:\n'
        '*$_inviteCode*\n\n'
        '📱 How to join:\n'
        '1. Open the LenDen app\n'
        '2. Go to Communities → tap the 🔗 link icon\n'
        '3. Enter the code: $_inviteCode\n'
        '$referralLine\n'
        '------------------\n'
        'LenDen – Split expenses effortlessly with friends & family. '
        'Track debts, settle instantly, and manage group expenses with ease.'
        '$downloadLine';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _communityColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.hub_rounded, color: _communityColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
              Text('$memberCount members · $groupCount groups',
                style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
            ])),
          ]),
          const SizedBox(height: 20),
          // Invite code display
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _communityColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _communityColor.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AppLocalizations.of(ctx).t('invite_code_display_label'),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppThemeColors.mutedText(ctx), letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Text(_inviteCode, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                    letterSpacing: 8, color: _communityColor)),
              ])),
              IconButton(
                icon: Icon(Icons.copy_rounded, color: _communityColor),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _inviteCode));
                  Navigator.pop(ctx);
                  _showSnack(AppLocalizations.of(context).t('invite_code_copied_snack'), icon: Icons.copy_rounded);
                },
              ),
            ]),
          ),
          const SizedBox(height: 14),
          // Share button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.share_rounded, color: Colors.white, size: 20),
              label: Text(AppLocalizations.of(ctx).t('share_invite_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _communityColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Share.share(msg, subject: 'Join $_name on LenDen');
              },
            ),
          ),
          const SizedBox(height: 10),
          // Copy full message
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: Icon(Icons.copy_all_rounded, color: _communityColor, size: 18),
              label: Text(AppLocalizations.of(ctx).t('copy_message_btn'),
                style: TextStyle(color: _communityColor, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _communityColor.withValues(alpha: 0.5), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: msg));
                Navigator.pop(ctx);
                _showSnack(AppLocalizations.of(context).t('message_copied_snack'), icon: Icons.copy_rounded);
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text(AppLocalizations.of(ctx).t('community_settings_title'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
          const SizedBox(height: 16),
          _settingsRow(ctx, Icons.copy_rounded, AppColors.cyan, AppLocalizations.of(ctx).t('copy_invite_code_label'), () {
            Clipboard.setData(ClipboardData(text: _inviteCode));
            Navigator.pop(ctx);
            _showSnack(AppLocalizations.of(context).t('invite_code_copied_snack'), icon: Icons.copy_rounded);
          }),
          const SizedBox(height: 8),
          // Allow direct add toggle
          StatefulBuilder(
            builder: (ctx2, setSt) {
              final allowDirect = (_community['settings'] as Map?)?['allowDirectAdd'] as bool? ?? true;
              return GestureDetector(
                onTap: () async {
                  final newVal = !allowDirect;
                  try {
                    final r = await ApiClient.patch('/api/communities/${widget.communityId}',
                      body: {'settings': {'allowDirectAdd': newVal}});
                    if (r.statusCode == 200) {
                      setState(() {
                        final s = Map<String, dynamic>.from((_community['settings'] as Map?) ?? {});
                        s['allowDirectAdd'] = newVal;
                        _community['settings'] = s;
                      });
                      setSt(() {});
                    }
                  } catch (_) {}
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppThemeColors.surfaceBg(ctx2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppThemeColors.border(ctx2)),
                  ),
                  child: Row(children: [
                    Container(width: 36, height: 36,
                      decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.person_add_rounded, color: AppColors.cyan, size: 18)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(AppLocalizations.of(ctx2).t('allow_direct_add_label'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(ctx2))),
                      Text(allowDirect ? AppLocalizations.of(ctx2).t('allow_direct_add_on_desc') : AppLocalizations.of(ctx2).t('allow_direct_add_off_desc'),
                        style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(ctx2))),
                    ])),
                    Switch(
                      value: allowDirect,
                      onChanged: null,
                      activeColor: AppColors.cyan,
                    ),
                  ]),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _settingsRow(ctx, Icons.camera_alt_rounded, const Color(0xFF00897B), AppLocalizations.of(ctx).t('upload_photo_label'), () {
            Navigator.pop(ctx);
            _pickAndUploadImage();
          }),
          const SizedBox(height: 8),
          _settingsRow(ctx, Icons.edit_rounded, const Color(0xFF8B5CF6), AppLocalizations.of(ctx).t('edit_community_label'), () {
            Navigator.pop(ctx);
            _showEditCommunity();
          }),
          const SizedBox(height: 8),
          _settingsRow(ctx, Icons.delete_rounded, Colors.red, AppLocalizations.of(ctx).t('delete_community_label'), () async {
            Navigator.pop(ctx);
            final confirm = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                backgroundColor: AppThemeColors.cardBg(d),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Text(AppLocalizations.of(d).t('delete_community_confirm_title'), style: TextStyle(color: AppThemeColors.primaryText(d), fontWeight: FontWeight.bold)),
                content: Text(AppLocalizations.of(d).t('delete_community_confirm_body'),
                  style: TextStyle(color: AppThemeColors.secondaryText(d))),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: Text(AppLocalizations.of(d).t('cancel'))),
                  ElevatedButton(onPressed: () => Navigator.pop(d, true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: Text(AppLocalizations.of(d).t('delete'))),
                ],
              ),
            );
            if (confirm == true) {
              try {
                final r = await ApiClient.delete('/api/communities/${widget.communityId}');
                if (r.statusCode == 200) { if (mounted) Navigator.pop(context); }
                else { _showSnack(jsonDecode(r.body)['error'] ?? 'Failed', isError: true); }
              } catch (e) { _showSnack(e.toString(), isError: true); }
            }
          }, isDestructive: true),
        ]),
      ),
    );
  }

  Widget _settingsRow(BuildContext ctx, IconData icon, Color color, String label, VoidCallback onTap, {bool isDestructive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppThemeColors.surfaceBg(ctx),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppThemeColors.border(ctx)),
        ),
        child: Row(children: [
          Container(width: 36, height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
              color: isDestructive ? Colors.red : AppThemeColors.primaryText(ctx))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _community.isEmpty) {
      return Scaffold(
        backgroundColor: AppThemeColors.scaffoldBg(context),
        body: const Center(child: CircularProgressIndicator(color: AppColors.cyan)),
      );
    }
    if (_error != null && _community.isEmpty) {
      return Scaffold(
        backgroundColor: AppThemeColors.scaffoldBg(context),
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: TextStyle(color: AppThemeColors.secondaryText(context))),
          TextButton(onPressed: _load, child: Text(AppLocalizations.of(context).t('retry_label'), style: const TextStyle(color: AppColors.cyan))),
        ])),
      );
    }

    final communityColor = _communityColor;
    final initials = _name.isNotEmpty ? _name[0].toUpperCase() : 'C';
    final imgUrl = '${ApiConfig.baseUrl}/api/communities/${widget.communityId}/image';
    final defImg = defaultCommunityImageUrl(_name);
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Column(children: [
        // ── Hero image banner ──────────────────────────────────────────
        SizedBox(
          height: 220 + topPad,
          child: Stack(fit: StackFit.expand, children: [
            // Background image (community photo or keyword default)
            Image.network(imgUrl, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Image.network(defImg, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [communityColor, Color.lerp(communityColor, Colors.black, 0.4)!],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                  ),
                ))),
            // Dark gradient overlay so text is readable
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x55000000), Color(0xDD000000)],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                ),
              ),
            ),
            // SafeArea content: top row + bottom info
            SafeArea(
              child: Column(children: [
                // Top row: back / settings / share
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  if (_isAdmin)
                    IconButton(
                      icon: const Icon(Icons.settings_rounded, color: Colors.white),
                      onPressed: _showSettings,
                    ),
                  if (_inviteCode.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.share_rounded, color: Colors.white),
                      onPressed: _showShareSheet,
                    ),
                ]),
                const Spacer(),
                // Community info overlay
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_name, style: const TextStyle(color: Colors.white, fontSize: 22,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.people_rounded, color: Colors.white70, size: 14),
                      const SizedBox(width: 5),
                      Text('${_members.length} ${_members.length == 1 ? AppLocalizations.of(context).t('member_singular') : AppLocalizations.of(context).t('member_plural')}  ·  ${_groups.length} ${_groups.length == 1 ? AppLocalizations.of(context).t('group_singular') : AppLocalizations.of(context).t('group_plural')}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                    if ((_community['description'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text((_community['description'] ?? '').toString(),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60, fontSize: 12,
                          fontStyle: FontStyle.italic, height: 1.4)),
                    ],
                  ]),
                ),
              ]),
            ),
          ]),
        ),

        // ── Tab bar ────────────────────────────────────────────────────
        Container(
          color: AppThemeColors.cardBg(context),
          child: TabBar(
            controller: _tabController,
            labelColor: communityColor,
            unselectedLabelColor: AppThemeColors.secondaryText(context),
            indicatorColor: communityColor,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: AppLocalizations.of(context).t('tab_overview')),
              Tab(text: AppLocalizations.of(context).t('tab_groups')),
              Tab(text: AppLocalizations.of(context).t('tab_members')),
              Tab(text: AppLocalizations.of(context).t('tab_feed')),
            ],
          ),
        ),

        // ── Tab content ────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverview(communityColor, initials, imgUrl),
              _buildGroupsTab(communityColor),
              _buildMembersTab(communityColor),
              _buildFeedTab(communityColor),
            ],
          ),
        ),
      ]),
    );
  }

  // ─── OVERVIEW TAB ───────────────────────────────────────────────────────────
  Widget _buildOverview(Color color, String initials, String imgUrl) {
    return RefreshIndicator(
      onRefresh: _load,
      color: color,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Community identity card
          _card(children: [
            Row(children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(15)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.network(imgUrl, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(child: Text(initials,
                      style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold),
                    )),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
                if ((_community['description'] ?? '').toString().isNotEmpty)
                  Text((_community['description'] ?? '').toString(),
                    style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context), height: 1.4)),
              ])),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              _miniStat(color, Icons.folder_shared_rounded, '${_groups.length}', AppLocalizations.of(context).t('tab_groups')),
              const SizedBox(width: 10),
              _miniStat(color, Icons.people_rounded, '${_members.length}', AppLocalizations.of(context).t('tab_members')),
            ]),
          ]),

          const SizedBox(height: 12),

          // Splits card — shows the total amount this user was split across all community groups
          _card(children: [
            Row(children: [
              Container(width: 38, height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.receipt_long_rounded, size: 20, color: color)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AppLocalizations.of(context).t('my_total_splits_label'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppThemeColors.mutedText(context), letterSpacing: 1.2)),
                const SizedBox(height: 2),
                _loadingBalance
                    ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('₹${_totalBalance.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
                        const SizedBox(height: 4),
                        if (_netBalance > 0.005)
                          Text('${AppLocalizations.of(context).t('you_owe_label').toUpperCase()}  ₹${_netBalance.abs().toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red))
                        else if (_netBalance < -0.005)
                          Text('${AppLocalizations.of(context).t('you_are_owed_label')}  ₹${_netBalance.abs().toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF00897B)))
                        else
                          Text(AppLocalizations.of(context).t('all_settled_label'),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF00897B))),
                      ]),
              ])),
            ]),
            if (_groupBalances.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: AppThemeColors.border(context)),
              const SizedBox(height: 10),
              ..._groupBalances.where((g) => (g['pendingAmount'] ?? g['amount'] ?? 0) != 0).map((g) {
                final pending = (g['pendingAmount'] ?? 0).toDouble();
                final gColor = _parseColor(g['color']);
                final isOwes = pending > 0.005;
                final isOwed = pending < -0.005;
                final amtColor = isOwes ? Colors.red : (isOwed ? const Color(0xFF00897B) : AppThemeColors.secondaryText(context));
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Container(width: 30, height: 30,
                      decoration: BoxDecoration(color: gColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text((g['title'] ?? 'G').toString()[0].toUpperCase(),
                        style: TextStyle(color: gColor, fontWeight: FontWeight.bold, fontSize: 13)))),
                    const SizedBox(width: 10),
                    Expanded(child: Text((g['title'] ?? '').toString(),
                      style: TextStyle(fontSize: 13, color: AppThemeColors.primaryText(context), fontWeight: FontWeight.w500))),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('₹${pending.abs().toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: amtColor)),
                      if (isOwes || isOwed)
                        Text(isOwes ? AppLocalizations.of(context).t('you_owe_small') : AppLocalizations.of(context).t('you_are_owed_small'),
                          style: TextStyle(fontSize: 10, color: amtColor, fontWeight: FontWeight.w500)),
                    ]),
                  ]),
                );
              }),
            ],
          ]),

          const SizedBox(height: 12),

          // Invite code card
          if (_inviteCode.isNotEmpty)
            _card(children: [
              Row(children: [
                Container(width: 38, height: 38,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(11)),
                  child: Icon(Icons.key_rounded, size: 20, color: color)),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppLocalizations.of(context).t('invite_code_display_label'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: AppThemeColors.mutedText(context), letterSpacing: 1.2)),
                  Text(_inviteCode, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                      letterSpacing: 8, color: color)),
                ]),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.copy_rounded, color: color, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _inviteCode));
                    _showSnack(AppLocalizations.of(context).t('code_copied_snack'), icon: Icons.copy_rounded);
                  },
                ),
              ]),
            ]),
        ],
      ),
    );
  }

  // ─── GROUPS TAB ─────────────────────────────────────────────────────────────
  Widget _buildGroupsTab(Color color) {
    return Column(children: [
      if (_isAdmin)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, AppColors.blue]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ElevatedButton.icon(
              onPressed: _addGroupToCommunity,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
              icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
              label: Text(AppLocalizations.of(context).t('add_group_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      Expanded(
        child: _groups.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 60, height: 60,
                  decoration: BoxDecoration(color: AppThemeColors.surfaceBg(context), borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppThemeColors.border(context))),
                  child: Icon(Icons.folder_open_rounded, size: 28, color: AppThemeColors.mutedText(context))),
                const SizedBox(height: 14),
                Text(AppLocalizations.of(context).t('no_groups_yet_label'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
                Text(_isAdmin ? AppLocalizations.of(context).t('add_group_link_hint') : AppLocalizations.of(context).t('ask_admin_groups_hint'),
                  style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context))),
              ]))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: _groups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final g = _groups[i];
                  final gId = (g['_id'] ?? g).toString();
                  final gName = (g['title'] ?? g['name'] ?? 'Group').toString();
                  final gColor = _parseColor(g['color']);
                  final gInitial = gName.isNotEmpty ? gName[0].toUpperCase() : 'G';
                  return GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => GroupDetailPage(groupId: gId, initialGroup: g is Map<String, dynamic> ? g : {}),
                    )).then((_) => _load()),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: gColor.withValues(alpha: 0.3)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        leading: Container(width: 42, height: 42,
                          decoration: BoxDecoration(color: gColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                          child: Center(child: Text(gInitial, style: TextStyle(color: gColor, fontWeight: FontWeight.bold, fontSize: 18)))),
                        title: Text(gName, style: TextStyle(fontWeight: FontWeight.w700, color: AppThemeColors.primaryText(context))),
                        trailing: _isAdmin
                            ? IconButton(
                                icon: Icon(Icons.remove_circle_outline_rounded, color: Colors.red.withValues(alpha: 0.7), size: 22),
                                tooltip: AppLocalizations.of(context).t('remove_from_community_tooltip'),
                                onPressed: () async {
                                  try {
                                    final r = await ApiClient.delete('/api/communities/${widget.communityId}/groups/$gId');
                                    if (r.statusCode == 200) { _load(); _showSnack(AppLocalizations.of(context).t('group_removed_community_snack')); }
                                    else { _showSnack(jsonDecode(r.body)['error'] ?? 'Failed', isError: true); }
                                  } catch (e) { _showSnack(e.toString(), isError: true); }
                                },
                              )
                            : const Icon(Icons.chevron_right_rounded, size: 20),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Future<void> _showAddMemberSheet(Color color) async {
    final emailCtrl = TextEditingController();
    bool sending = false;
    final allowDirect = (_community['settings'] as Map?)?['allowDirectAdd'] as bool? ?? true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(ctx),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                Container(width: 40, height: 40,
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [color, Color.lerp(color, AppColors.blue, 0.5)!]), borderRadius: BorderRadius.circular(12)),
                  child: Icon(allowDirect ? Icons.person_add_rounded : Icons.mail_rounded, color: Colors.white, size: 20)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(allowDirect ? AppLocalizations.of(ctx).t('add_member_title') : AppLocalizations.of(ctx).t('send_invite_title'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
                  Text(allowDirect ? AppLocalizations.of(ctx).t('direct_add_mode_desc') : AppLocalizations.of(ctx).t('invite_mode_desc'),
                    style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(ctx))),
                ])),
              ]),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: AppThemeColors.surfaceBg(ctx),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
                ),
                child: TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: AppThemeColors.primaryText(ctx)),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(ctx).t('enter_email_hint'),
                    hintStyle: TextStyle(color: AppThemeColors.mutedText(ctx)),
                    prefixIcon: Icon(Icons.email_outlined, color: color, size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color, Color.lerp(color, AppColors.blue, 0.5)!]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: sending ? null : () async {
                    final email = emailCtrl.text.trim();
                    if (email.isEmpty) return;
                    setSheet(() => sending = true);
                    try {
                      final r = await ApiClient.post('/api/communities/${widget.communityId}/members', body: {'email': email});
                      final body = jsonDecode(r.body);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (r.statusCode == 200) {
                        _load();
                        _showSnack(body['message'] ?? (allowDirect ? 'Member added!' : 'Invite sent!'),
                          icon: allowDirect ? Icons.person_add_rounded : Icons.mail_rounded);
                      } else {
                        _showSnack(body['error'] ?? 'Failed', isError: true);
                      }
                    } catch (e) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showSnack(e.toString(), isError: true);
                    }
                  },
                  child: sending
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(allowDirect ? AppLocalizations.of(ctx).t('add_member_title') : AppLocalizations.of(ctx).t('send_invite_title'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ─── MEMBERS TAB ────────────────────────────────────────────────────────────
  Widget _buildMembersTab(Color color) {
    return Column(children: [
      // Invite header
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Icon(Icons.people_rounded, color: color, size: 18),
            const SizedBox(width: 8),
            Text('${_members.length} ${_members.length == 1 ? AppLocalizations.of(context).t('member_singular') : AppLocalizations.of(context).t('member_plural')}',
              style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13)),
            const Spacer(),
            if (_isAdmin)
              GestureDetector(
                onTap: () => _showAddMemberSheet(color),
                child: Row(children: [
                  Icon(Icons.person_add_rounded, color: color, size: 15),
                  const SizedBox(width: 4),
                  Text(AppLocalizations.of(context).t('add_btn'), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                ]),
              ),
            if (_inviteCode.isNotEmpty)
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _inviteCode));
                  _showSnack(AppLocalizations.of(context).t('invite_code_copied_snack'), icon: Icons.copy_rounded);
                },
                child: Row(children: [
                  Icon(Icons.link_rounded, color: color, size: 15),
                  const SizedBox(width: 4),
                  Text(AppLocalizations.of(context).t('invite_label'), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
        ),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          itemCount: _members.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final m = _members[i];
            final user = m['user'] is Map ? m['user'] : <String, dynamic>{};
            final _oid = RegExp(r'^[0-9a-f]{24}$');
            String _sanitize(dynamic v, String fb) {
              final s = (v ?? '').toString();
              return s.isEmpty || _oid.hasMatch(s) ? fb : s;
            }
            final rawName = _sanitize(user['name'], '');
            final rawEmail = _sanitize(user['email'], '');
            final mName = rawName.isNotEmpty ? rawName : (rawEmail.isNotEmpty ? rawEmail : (user.isEmpty ? AppLocalizations.of(context).t('deleted_account_label') : AppLocalizations.of(context).t('member_singular')));
            final mEmail = rawEmail;
            final role = (m['role'] ?? 'member').toString();
            final isMe = (user['_id'] ?? '').toString() == _uid;

            return Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: role == 'admin'
                    ? color.withValues(alpha: 0.25)
                    : AppThemeColors.border(context).withValues(alpha: 0.5)),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 42, height: 42,
                    child: Image.network(
                      '${ApiConfig.baseUrl}/api/users/${(user['_id'] ?? '').toString()}/profile-image',
                      width: 42, height: 42, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: (role == 'admin' ? color : AppThemeColors.surfaceBg(context)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: Text(
                          mName.isNotEmpty ? mName[0].toUpperCase() : 'M',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18,
                            color: role == 'admin' ? Colors.white : AppThemeColors.secondaryText(context)),
                        )),
                      ),
                    ),
                  ),
                ),
                title: Row(children: [
                  Flexible(child: Text(mName, style: TextStyle(fontWeight: FontWeight.w700,
                      color: AppThemeColors.primaryText(context)))),
                  if (isMe) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: AppThemeColors.surfaceBg(context), borderRadius: BorderRadius.circular(20)),
                      child: Text(AppLocalizations.of(context).t('you_chip_label'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: AppThemeColors.secondaryText(context))),
                    ),
                  ],
                ]),
                subtitle: Text(mEmail, style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: role == 'admin' ? color.withValues(alpha: 0.10) : AppThemeColors.surfaceBg(context),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: role == 'admin' ? color.withValues(alpha: 0.3) : AppThemeColors.border(context)),
                  ),
                  child: Text(
                    role == 'admin' ? AppLocalizations.of(context).t('role_admin_badge') : AppLocalizations.of(context).t('role_member_badge'),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: role == 'admin' ? color : AppThemeColors.secondaryText(context)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ─── HELPERS ────────────────────────────────────────────────────────────────
  Widget _card({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppThemeColors.border(context).withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _miniStat(Color color, IconData icon, String value, String label) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: AppThemeColors.secondaryText(context))),
        ]),
      ]),
    ));
  }

  // ─── FEED TAB ────────────────────────────────────────────────────────────────
  Widget _buildFeedTab(Color color) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final hasAccess = session.hasFeature('community_feed');
    final userId = session.user?['_id']?.toString() ?? '';

    if (!hasAccess) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
              child: Icon(Icons.lock_rounded, color: color, size: 34),
            ),
            const SizedBox(height: 20),
            Text(AppLocalizations.of(context).t('community_feed_title'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 8),
            Text(AppLocalizations.of(context).t('community_feed_subscribe_desc'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context), height: 1.5)),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, Color.lerp(color, AppColors.blue, 0.5)!]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                  minimumSize: const Size(200, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0,
                ),
                icon: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 18),
                label: Text(AppLocalizations.of(context).t('upgrade_to_subscribe_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () => _showSnack(AppLocalizations.of(context).t('subscribe_for_feed_snack'), icon: Icons.info_outline_rounded),
              ),
            ),
          ]),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppThemeColors.border(context)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            Row(children: [
              _profileAvatar(userId, size: 38, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppThemeColors.surfaceBg(context),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppThemeColors.border(context)),
                  ),
                  child: Text(AppLocalizations.of(context).t('feed_write_placeholder'),
                    style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13)),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: color,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                onPressed: () => _showSnack(AppLocalizations.of(context).t('community_feed_coming_soon_snack')),
                child: Text(AppLocalizations.of(context).t('publish_post_btn'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 40),
        Center(child: Column(children: [
          Container(width: 64, height: 64,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18)),
            child: Icon(Icons.forum_outlined, color: color, size: 30)),
          const SizedBox(height: 14),
          Text(AppLocalizations.of(context).t('community_feed_coming_soon'),
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 6),
          Text(AppLocalizations.of(context).t('community_feed_coming_soon_desc'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context), height: 1.5)),
        ])),
      ],
    );
  }

  Widget _profileAvatar(String userId, {double size = 38, Color? color}) {
    final fallback = color ?? AppColors.cyan;
    if (userId.isEmpty) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(color: fallback.withValues(alpha: 0.10), shape: BoxShape.circle),
        child: Icon(Icons.person_rounded, color: fallback, size: size * 0.5),
      );
    }
    return ClipOval(
      child: Image.network(
        '${ApiConfig.baseUrl}/api/users/$userId/profile-image',
        width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size, height: size,
          decoration: BoxDecoration(color: fallback.withValues(alpha: 0.10), shape: BoxShape.circle),
          child: Icon(Icons.person_rounded, color: fallback, size: size * 0.5),
        ),
      ),
    );
  }
}
