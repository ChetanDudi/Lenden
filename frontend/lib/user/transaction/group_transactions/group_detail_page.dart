import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/currency_display.dart';
import '../../../utils/currency_provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:share_plus/share_plus.dart';
import '../../../utils/share_utils.dart';
import 'group_members_page.dart';
import 'group_expenses_page.dart';
import 'group_stats_page.dart';
import 'group_request_payment_page.dart';
import 'group_process_payment_page.dart';
import '../../wallet/widgets/payment_sheet.dart';
import '../../../widgets/payment_success_page.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import '../../../utils/image_picker_utils.dart';
import '../../../widgets/share_as_note_sheet.dart';

const _kCardColors = [
  Color(0xFFFFF4E6), Color(0xFFE8F5E9), Color(0xFFFCE4EC),
  Color(0xFFE3F2FD), Color(0xFFFFF9C4), Color(0xFFF3E5F5),
];

String _fmtDt(dynamic dt) {
  if (dt == null) return '';
  try {
    final d = dt is String ? DateTime.parse(dt).toLocal() : dt as DateTime;
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final period = d.hour >= 12 ? 'PM' : 'AM';
    return '${months[d.month - 1]} ${d.day}, ${d.year}  $h:$m $period';
  } catch (_) {
    return '';
  }
}

Widget _tricolorBorderBox({
  required Widget child,
  double radius = 18,
  double borderWidth = 2,
  EdgeInsetsGeometry? margin,
}) {
  return Container(
    margin: margin,
    decoration: BoxDecoration(
      gradient: AppColors.tricolorGradient,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    padding: EdgeInsets.all(borderWidth),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius - borderWidth),
      child: child,
    ),
  );
}

final _oidRe = RegExp(r'^[0-9a-f]{24}$');
String _emailOf(dynamic field) {
  if (field == null) return '-';
  if (field is Map) {
    final e = (field['email'] ?? '').toString();
    return _oidRe.hasMatch(e) || e.isEmpty ? (field['name']?.toString().isNotEmpty == true ? field['name'].toString() : 'Deleted Account') : e;
  }
  final s = field.toString();
  return _oidRe.hasMatch(s) ? 'Deleted Account' : s;
}

class GroupDetailPage extends StatefulWidget {
  final String groupId;
  final Map<String, dynamic> initialGroup;

  const GroupDetailPage({
    super.key,
    required this.groupId,
    required this.initialGroup,
  });

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage>
    with CurrencyDisplayMixin<GroupDetailPage> {
  late Map<String, dynamic> _group;
  bool _loading = false;
  bool _uploadingImage = false;
  String? _error;
  String? _userEmail;
  bool _isCreator = false;
  List<Map<String, dynamic>> _communities = [];

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup;
    final session = Provider.of<SessionProvider>(context, listen: false);
    _userEmail = session.user?['email'] ?? '';
    final creatorEmail = _emailOf(_group['creator']).toLowerCase();
    _isCreator = creatorEmail == _userEmail!.toLowerCase();
    loadCurrencies();
    _loadCommunities();
    // If initialGroup is a stub (from community page — no members/expenses), fetch full data
    final hasFullData = (_group['members'] is List) && (_group['expenses'] is List);
    if (!hasFullData) _loadGroup();
  }

  Future<void> _loadGroup() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get('/api/group-transactions/${widget.groupId}/detail');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _group = Map<String, dynamic>.from(data);
          final creatorEmail = _emailOf(_group['creator']).toLowerCase();
          _isCreator = creatorEmail == _userEmail!.toLowerCase();
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _parseCommunityColor(dynamic c) {
    try {
      if (c is String && c.startsWith('#')) {
        return Color(int.parse('FF${c.replaceFirst('#', '')}', radix: 16));
      }
    } catch (_) {}
    return AppColors.cyan;
  }

  Future<void> _loadCommunities() async {
    try {
      final res = await ApiClient.get('/api/group-transactions/${widget.groupId}/communities');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) setState(() => _communities = List<Map<String, dynamic>>.from(data['communities'] ?? []));
      }
    } catch (_) {}
  }

  void _showCommunitiesSheet() async {
    List<Map<String, dynamic>> adminCommunities = [];
    try {
      final res = await ApiClient.get('/api/communities');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final uid = Provider.of<SessionProvider>(context, listen: false).user?['_id']?.toString() ?? '';
        final all = List<Map<String, dynamic>>.from(data['communities'] ?? []);
        final groupCommunityIds = _communities.map((c) => (c['_id'] ?? '').toString()).toSet();
        adminCommunities = all.where((c) {
          final cId = (c['_id'] ?? '').toString();
          if (groupCommunityIds.contains(cId)) return false;
          final members = (c['members'] as List?) ?? [];
          return members.any((m) => (m['user'] is Map ? (m['user'] as Map)['_id'] : m['user'])?.toString() == uid && m['role'] == 'admin');
        }).toList();
      }
    } catch (_) {}
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(20, 20, 20, 32 + MediaQuery.of(ctx).padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Container(width: 40, height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.groups_rounded, color: Colors.white, size: 20)),
              const SizedBox(width: 12),
              Text(AppLocalizations.of(ctx).t('communities_title'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(ctx))),
              const Spacer(),
              if (adminCommunities.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 16, color: AppColors.cyan),
                  label: Text(AppLocalizations.of(ctx).t('add'), style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _showAddToCommunityPicker(adminCommunities);
                  },
                ),
            ]),
            const SizedBox(height: 12),
            if (_communities.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 56, height: 56,
                    decoration: BoxDecoration(color: AppThemeColors.surfaceBg(ctx), borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppThemeColors.border(ctx))),
                    child: Icon(Icons.groups_outlined, size: 28, color: AppThemeColors.mutedText(ctx))),
                  const SizedBox(height: 10),
                  Text(AppLocalizations.of(ctx).t('not_in_any_community_label'),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppThemeColors.secondaryText(ctx))),
                  if (adminCommunities.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                      label: Text(AppLocalizations.of(ctx).t('add_to_community_label'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _showAddToCommunityPicker(adminCommunities);
                      },
                    ),
                  ],
                ]),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.45),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _communities.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = _communities[i];
                    final cId = (c['_id'] ?? '').toString();
                    final cName = (c['name'] ?? 'Community').toString();
                    final cColor = _parseCommunityColor(c['color']);
                    final cMembers = (c['members'] as List?) ?? [];
                    final uid = Provider.of<SessionProvider>(ctx, listen: false).user?['_id']?.toString() ?? '';
                    final isAdmin = cMembers.any((m) =>
                      (m['user'] is Map ? (m['user'] as Map)['_id'] : m['user'])?.toString() == uid && m['role'] == 'admin');
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppThemeColors.surfaceBg(ctx),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        Container(width: 38, height: 38,
                          decoration: BoxDecoration(color: cColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                          child: Center(child: Text(cName.isNotEmpty ? cName[0].toUpperCase() : 'C',
                            style: TextStyle(color: cColor, fontWeight: FontWeight.bold, fontSize: 16)))),
                        const SizedBox(width: 12),
                        Expanded(child: Text(cName, style: TextStyle(fontWeight: FontWeight.w600,
                            color: AppThemeColors.primaryText(ctx)))),
                        if (isAdmin)
                          GestureDetector(
                            onTap: () async {
                              Navigator.pop(ctx);
                              try {
                                final r = await ApiClient.delete(
                                  '/api/group-transactions/${widget.groupId}/communities/$cId');
                                if (r.statusCode == 200) {
                                  _loadCommunities();
                                  _showSnack(AppLocalizations.of(context).t('removed_from_community_snack'), success: true);
                                } else {
                                  _showError(jsonDecode(r.body)['error'] ?? 'Failed');
                                }
                              } catch (e) { _showError(e.toString()); }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8)),
                              child: const Icon(Icons.remove_circle_outline_rounded, color: Colors.red, size: 18),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: cColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                            child: Text(AppLocalizations.of(ctx).t('role_member_badge'), style: TextStyle(color: cColor, fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                      ]),
                    );
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _showAddToCommunityPicker(List<Map<String, dynamic>> communities) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(20, 20, 20, 32 + MediaQuery.of(ctx).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            Container(width: 40, height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 20)),
            const SizedBox(width: 12),
            Text(AppLocalizations.of(ctx).t('add_to_community_label'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(ctx))),
          ]),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.45),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: communities.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final c = communities[i];
                final cId = (c['_id'] ?? '').toString();
                final cName = (c['name'] ?? 'Community').toString();
                final cColor = _parseCommunityColor(c['color']);
                return GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      final r = await ApiClient.post(
                        '/api/group-transactions/${widget.groupId}/communities',
                        body: {'communityId': cId},
                      );
                      if (r.statusCode == 200) {
                        _loadCommunities();
                        _showSnack(AppLocalizations.of(context).t('group_added_community_snack'), success: true);
                      } else {
                        _showError(jsonDecode(r.body)['error'] ?? 'Failed');
                      }
                    } catch (e) { _showError(e.toString()); }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppThemeColors.surfaceBg(ctx),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Container(width: 38, height: 38,
                        decoration: BoxDecoration(color: cColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                        child: Center(child: Text(cName.isNotEmpty ? cName[0].toUpperCase() : 'C',
                          style: TextStyle(color: cColor, fontWeight: FontWeight.bold, fontSize: 16)))),
                      const SizedBox(width: 12),
                      Expanded(child: Text(cName, style: TextStyle(fontWeight: FontWeight.w600,
                          color: AppThemeColors.primaryText(ctx)))),
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

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get('/api/group-transactions/user-groups');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final groups =
            List<Map<String, dynamic>>.from(data['groups'] ?? []);
        final updated = groups.firstWhere(
          (g) => g['_id'].toString() == widget.groupId,
          orElse: () => _group,
        );
        if (mounted) setState(() => _group = updated);
      } else {
        if (mounted) setState(() => _error = 'Failed to load group details. Please try again.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load group details. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickGroupImage() async {
    if (!_isCreator) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppThemeColors.divider(ctx),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Group Icon', style: TextStyle(fontWeight: FontWeight.bold,
                fontSize: 17, color: AppThemeColors.primaryText(ctx))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: AppColors.cyan),
              title: Text('Take photo', style: TextStyle(color: AppThemeColors.primaryText(ctx))),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.cyan),
              title: Text('Choose from gallery', style: TextStyle(color: AppThemeColors.primaryText(ctx))),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (_group['groupImageUrl'] != null && _group['groupImageUrl'].toString().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text('Remove photo', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const Divider(height: 20),
            Text('Preset Colors', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx), fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                Colors.teal, Colors.deepPurple, Colors.indigo, Colors.blue,
                Colors.green, Colors.orange, Colors.pink, Colors.red,
                Colors.brown, Colors.blueGrey,
              ].map((c) => GestureDetector(
                onTap: () => Navigator.pop(ctx, 'color:${c.toARGB32()}'),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c.toARGB32() == _groupColor.toARGB32() ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 4)],
                  ),
                  child: c.toARGB32() == _groupColor.toARGB32()
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              )).toList(),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );

    if (action == 'remove') {
      setState(() => _uploadingImage = true);
      try {
        final res = await ApiClient.delete('/api/group-transactions/${widget.groupId}/image');
        if (res.statusCode == 200 && mounted) {
          setState(() => _group = {..._group, 'groupImageUrl': null});
        }
      } finally {
        if (mounted) setState(() => _uploadingImage = false);
      }
      return;
    }

    if (action != null && action.startsWith('color:')) {
      final colorInt = int.tryParse(action.substring(6));
      if (colorInt == null) return;
      final hexColor = '#${colorInt.toRadixString(16).substring(2).toUpperCase()}';
      await ApiClient.put('/api/group-transactions/${widget.groupId}/color', body: {'color': hexColor});
      if (mounted) _refresh();
      return;
    }

    if (action == null) return;

    final result = await ImagePickerUtils.pickAndCrop(
      context,
      source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
    );
    if (result == null || !mounted) return;

    setState(() => _uploadingImage = true);
    try {
      final res = await ApiClient.putMultipart(
        '/api/group-transactions/${widget.groupId}/image',
        files: [ApiMultipartFile(field: 'groupImage', filename: result.file.name, bytes: result.bytes)],
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _group = {..._group, 'groupImageUrl': data['groupImageUrl']});
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload image'), backgroundColor: Colors.red),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload image'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  void _showGroupPaymentSuccess(BuildContext ctx, String toEmail, double amount) {
    final t = AppLocalizations.of(ctx).t;
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => PaymentSuccessPage(
          title: t('payment_successful_exclaim'),
          amount: amount,
          recipientName: toEmail,
          transactionType: t('group_expense_repayment_label'),
        ),
      ),
    );
  }

  String _resolveEmail(dynamic userField) {
    if (userField == null) return 'Deleted Account';
    // Fast path: already an email string
    if (userField is String && userField.contains('@')) return userField;
    final direct = _emailOf(userField);
    if (direct.contains('@')) return direct;
    // Extract the ObjectId to search for in the members list
    final String rawId;
    if (userField is Map) {
      rawId = (userField['_id'] ?? userField['id'] ?? '').toString();
    } else {
      rawId = userField.toString();
    }
    if (rawId.isNotEmpty) {
      for (final m in List<dynamic>.from(_group['members'] ?? [])) {
        // Match on member subdoc _id
        final memberId = (m['_id'] ?? '').toString();
        if (memberId.isNotEmpty && memberId == rawId) {
          final email = (m['email'] ?? '').toString();
          if (email.contains('@')) return email;
        }
        // Match on member's user field (populated or raw)
        final mUser = m['user'];
        final mId = mUser is Map
            ? (mUser['_id'] ?? mUser['id'] ?? '').toString()
            : (mUser ?? '').toString();
        if (mId.isNotEmpty && mId == rawId) {
          final email = (m['email'] ?? _emailOf(mUser)).toString();
          if (email.contains('@')) return email;
        }
      }
    }
    return _oidRe.hasMatch(rawId) ? 'Deleted Account' : (direct == 'Deleted Account' ? 'Deleted Account' : direct);
  }

  Color get _groupColor {
    if (_group['color'] != null) {
      try {
        return Color(int.parse(
            _group['color'].toString().replaceFirst('#', '0xff')));
      } catch (_) {}
    }
    return AppColors.cyan;
  }

  Future<void> _updateColor() async {
    final t = AppLocalizations.of(context).t;
    Color picked = _groupColor;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('change_group_color_label')),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (c) => picked = c,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('cancel'))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final hexColor =
                  '#${picked.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
              await ApiClient.post(
                '/api/group-transactions/${widget.groupId}/color',
                body: {'color': hexColor},
              );
              _refresh();
            },
            child: Text(t('apply_label')),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteGroup() async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.warning_rounded, color: Colors.red),
          const SizedBox(width: 8),
          Text(t('delete_group_title'), style: const TextStyle(color: Colors.red)),
        ]),
        content: Text(
          t('delete_group_confirm_message').replaceFirst('{title}', '${_group['title']}'),
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child:
                Text(t('delete'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    final res =
        await ApiClient.delete('/api/group-transactions/${widget.groupId}');
    if (!mounted) return;
    setState(() => _loading = false);
    if (res.statusCode == 200) {
      Navigator.pop(context, 'deleted');
    } else {
      _showError(jsonDecode(res.body)['error'] ?? t('failed_to_delete_group_message'));
    }
  }

  Future<void> _confirmLeave() async {
    final t = AppLocalizations.of(context).t;
    // Check pending expenses
    final expenses = List<dynamic>.from(_group['expenses'] ?? []);
    double pendingAmount = 0;
    for (final exp in expenses) {
      for (final split in (exp['split'] ?? [])) {
        if (_emailOf(split['user']).toLowerCase() ==
            _userEmail!.toLowerCase()) {
          if (split['settled'] != true) {
            pendingAmount += ((split['amount'] ?? 0) as num).toDouble();
          }
        }
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: _tricolorBorderBox(
          radius: 22,
          child: Container(
            decoration: BoxDecoration(color: AppThemeColors.cardBg(context)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header band
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.exit_to_app_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        t('leave_group_title_message').replaceFirst('{title}', '${_group['title']}'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info items
                      _leaveInfoRow(
                        Icons.people_outline_rounded,
                        t('marked_as_left_in_group_message'),
                        Colors.blueGrey,
                      ),
                      const SizedBox(height: 8),
                      _leaveInfoRow(
                        Icons.receipt_long_rounded,
                        t('balance_auto_settled_message'),
                        Colors.green[700]!,
                      ),
                      const SizedBox(height: 8),
                      _leaveInfoRow(
                        Icons.person_add_rounded,
                        t('creator_can_readd_later_message'),
                        Colors.purple[700]!,
                      ),
                      if (pendingAmount > 0) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.orange[300]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_rounded,
                                  color: Colors.orange[700],
                                  size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  t('pending_expenses_auto_settle_message').replaceFirst('{amount}', pendingAmount.toStringAsFixed(2)),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange[800]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(context, false),
                            child: Text(t('cancel')),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              gradient: AppColors.tricolorGradient,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange[700],
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10),
                              ),
                              icon: const Icon(
                                  Icons.exit_to_app_rounded,
                                  color: Colors.white,
                                  size: 18),
                              label: Text(t('leave_label'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                              onPressed: () =>
                                  Navigator.pop(context, true),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return;
    setState(() => _loading = true);
    final res = await ApiClient.post(
        '/api/group-transactions/${widget.groupId}/leave');
    if (!mounted) return;
    setState(() => _loading = false);
    if (res.statusCode == 200) {
      _showSnack(t('you_have_left_the_group_message'), success: true);
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.pop(context, 'left');
    } else {
      final body = jsonDecode(res.body);
      if (res.statusCode == 400 &&
          (body['error'] ?? '').toString().contains('pending')) {
        await ApiClient.post(
            '/api/group-transactions/${widget.groupId}/send-leave-request');
        _showSnack(t('leave_request_sent_to_members_message'), success: true);
      } else {
        _showError(body['error'] ?? t('failed_to_leave_group_message'));
      }
    }
  }

  Widget _leaveInfoRow(IconData icon, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context))),
        ),
      ],
    );
  }

  Future<void> _showInviteSheet(BuildContext context, String Function(String) t) async {
    String? currentCode = _group['joinCode']?.toString();
    bool generating = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppThemeColors.divider(context), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00796B).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.link_rounded, color: Color(0xFF00796B), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(t('invite_label'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
                ],
              ),
              const SizedBox(height: 16),
              if (currentCode != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00796B).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00796B).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('join_code_label'), style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
                            const SizedBox(height: 4),
                            Text(currentCode ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold,
                                letterSpacing: 4, color: Color(0xFF00796B))),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: Color(0xFF00796B)),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: currentCode!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(t('join_code_copied_label')), duration: const Duration(seconds: 2)),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.share_rounded, color: Colors.white, size: 20),
                    label: const Text('Share Invite', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00796B),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      final groupTitle = (_group['title'] ?? 'Our Group').toString();
                      final memberCount = (_group['members'] as List?)?.length ?? 0;
                      final appLink = await fetchAppInviteLink();
                      final myReferralCode = await fetchReferralCode();
                      final downloadLine = appLink.isNotEmpty ? '\n📥 Download LenDen: $appLink' : '';
                      final referralLine = myReferralCode.isNotEmpty
                          ? '\n🎁 *Referral Code: $myReferralCode*\n'
                            '   (New to LenDen? Enter this code on sign-up to earn bonus coins!)'
                          : '';
                      final msg = '🎉 You\'re invited to join *$groupTitle* on LenDen!\n\n'
                          '👥 Group: $groupTitle\n'
                          '👤 Members: $memberCount\n\n'
                          '🔑 Your Invite Code:\n'
                          '*${currentCode!}*\n\n'
                          '📱 How to join:\n'
                          '1. Open the LenDen app\n'
                          '2. Go to Groups → tap the 🔗 link icon\n'
                          '3. Enter the code: ${currentCode!}\n'
                          '$referralLine\n'
                          '------------------\n'
                          'LenDen – Split expenses effortlessly with friends & family. '
                          'Track debts, settle instantly, and manage group expenses with ease.'
                          '$downloadLine';
                      Share.share(msg, subject: 'Join $groupTitle on LenDen');
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.note_add_rounded, color: AppColors.tricolorGreen, size: 20),
                    label: const Text('Share as Note', style: TextStyle(color: AppColors.tricolorGreen, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.tricolorGreen, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      final groupTitle = (_group['title'] ?? 'Our Group').toString();
                      final memberCount = (_group['members'] as List?)?.length ?? 0;
                      final code = currentCode ?? '';
                      final noteContent = 'Group: $groupTitle\nMembers: $memberCount${code.isNotEmpty ? '\nJoin Code: $code' : ''}';
                      await showShareAsNoteSheet(ctx, title: 'Join $groupTitle on LenDen', content: noteContent);
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Text(t('share_join_code_info'), style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(t('regenerate_label')),
                        onPressed: generating ? null : () async {
                          setSheet(() => generating = true);
                          final res = await ApiClient.post('/api/group-transactions/${widget.groupId}/join-code', body: {});
                          if (res.statusCode == 200) {
                            final code = jsonDecode(res.body)['joinCode']?.toString();
                            setSheet(() { currentCode = code; generating = false; });
                            if (!mounted) return;
                            setState(() => _group['joinCode'] = code);
                          } else {
                            setSheet(() => generating = false);
                            if (!mounted) return;
                            final err = (jsonDecode(res.body)['error'] ?? 'Failed to regenerate code').toString();
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.link_off_rounded, size: 18, color: Colors.red),
                        label: Text(t('disable_label'), style: const TextStyle(color: Colors.red)),
                        onPressed: generating ? null : () async {
                          setSheet(() => generating = true);
                          final res = await ApiClient.delete('/api/group-transactions/${widget.groupId}/join-code');
                          if (res.statusCode == 200) {
                            setSheet(() { currentCode = null; generating = false; });
                            if (!mounted) return;
                            setState(() => _group['joinCode'] = null);
                          } else {
                            setSheet(() => generating = false);
                            if (!mounted) return;
                            final err = (jsonDecode(res.body)['error'] ?? 'Failed to disable join code').toString();
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                          }
                        },
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Text(t('no_join_code_yet'), style: TextStyle(color: AppThemeColors.secondaryText(context))),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: generating
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.add_link_rounded, color: Colors.white),
                    label: Text(t('generate_code_label'), style: const TextStyle(color: Colors.white)),
                    onPressed: generating ? null : () async {
                      setSheet(() => generating = true);
                      final res = await ApiClient.post('/api/group-transactions/${widget.groupId}/join-code', body: {});
                      if (res.statusCode == 200) {
                        final code = jsonDecode(res.body)['joinCode']?.toString();
                        setSheet(() { currentCode = code; generating = false; });
                        setState(() => _group['joinCode'] = code);
                      } else {
                        setSheet(() => generating = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00796B),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text(msg,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
        backgroundColor: const Color(0xFFD32F2F),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(14),
        elevation: 6,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.info_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(msg,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
        backgroundColor:
            success ? const Color(0xFF2E7D32) : Colors.blue[700],
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(14),
        elevation: 6,
      ),
    );
  }

  // Minimum transactions to settle all debts given net balances.
  List<Map<String, dynamic>> _computePairwiseDebts(Map<String, double> balances) {
    final debtors = <String, double>{};
    final creditors = <String, double>{};
    for (final e in balances.entries) {
      if (e.value > 0.01) debtors[e.key] = e.value;
      if (e.value < -0.01) creditors[e.key] = -e.value;
    }
    final dKeys = debtors.keys.toList();
    final cKeys = creditors.keys.toList();
    final dAmts = dKeys.map((k) => debtors[k]!).toList();
    final cAmts = cKeys.map((k) => creditors[k]!).toList();
    final result = <Map<String, dynamic>>[];
    int di = 0, ci = 0;
    while (di < dKeys.length && ci < cKeys.length) {
      final pay = dAmts[di] < cAmts[ci] ? dAmts[di] : cAmts[ci];
      result.add({'from': dKeys[di], 'to': cKeys[ci], 'amount': pay});
      dAmts[di] -= pay;
      cAmts[ci] -= pay;
      if (dAmts[di] < 0.01) di++;
      if (cAmts[ci] < 0.01) ci++;
    }
    return result;
  }

  // Compute net balance per member from expenses data.
  // Positive = this member owes others; Negative = others owe this member.
  Map<String, double> _computeBalances() {
    final expenses = List<dynamic>.from(_group['expenses'] ?? []);
    final members = List<dynamic>.from(_group['members'] ?? []);
    if (expenses.isEmpty) return {};

    final Map<String, double> net = {};

    // Seed all active members at 0
    for (final m in members) {
      final email = _resolveEmail(m['user'] ?? m).toLowerCase();
      if (email.contains('@')) net[email] = 0;
    }

    for (final exp in expenses) {
      final addedByEmail = _resolveEmail(exp['addedBy']).toLowerCase();
      final splits = List<dynamic>.from(exp['split'] ?? []);
      for (final s in splits) {
        final splitEmail = _resolveEmail(s['user']).toLowerCase();
        final amount = ((s['amount'] ?? 0) as num).toDouble();
        final settled = s['settled'] == true;
        if (settled) continue;
        if (splitEmail == addedByEmail) continue; // payer doesn't owe themselves
        // splitEmail owes addedByEmail `amount`
        net[splitEmail] = (net[splitEmail] ?? 0) + amount;
        net[addedByEmail] = (net[addedByEmail] ?? 0) - amount;
      }
    }

    // Apply recorded peer-to-peer payments: each payment reduces the payer's
    // outstanding debt and reduces what the receiver is still owed.
    for (final p in List<dynamic>.from(_group['memberPayments'] ?? [])) {
      final from = (p['from'] as String? ?? '').toLowerCase();
      final to = (p['to'] as String? ?? '').toLowerCase();
      final amt = ((p['amount'] ?? 0) as num).toDouble();
      net[from] = (net[from] ?? 0) - amt;
      net[to] = (net[to] ?? 0) + amt;
    }

    // Remove zeroes
    net.removeWhere((_, v) => v.abs() < 0.01);
    return net;
  }

  void _showDescriptionSheet(BuildContext context, String Function(String) t) {
    final desc = (_group['description'] ?? '').toString();
    final groupColor = _groupColor;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2))),
            )),
            // Header strip
            Container(
              margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [groupColor, groupColor.withValues(alpha: 0.6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.info_outline_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Group Description', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(_group['title']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
              ]),
            ),
            // Description body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                child: Text(
                  desc.isNotEmpty ? desc : 'No description set.',
                  style: TextStyle(fontSize: 15, height: 1.6, color: desc.isNotEmpty ? AppThemeColors.primaryText(ctx) : AppThemeColors.mutedText(ctx)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Service bar items ───────────────────────────────────────────
  Widget _serviceChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    int? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10)),
                child: Text('$badge',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Stat card ───────────────────────────────────────────────────
  Widget _statCard(String value, String label, IconData icon, Color color) {
    return Container(
      width: 110,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context)),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final members =
        List<dynamic>.from(_group['members'] ?? []);
    final activeMembers =
        members.where((m) => m['leftAt'] == null).length;
    final expenses =
        List<dynamic>.from(_group['expenses'] ?? []);
    final title = _group['title'] ?? t('group_label');

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          // Header wave
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipPath(
              clipper: _WaveClipper(),
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_groupColor, _groupColor.withValues(alpha: 0.6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top bar
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2)),
                        ),
                      IconButton(
                        icon: const Icon(Icons.currency_exchange_rounded, color: Colors.white),
                        onPressed: () {
                          final currencies = currencyData?.currencies ?? kCurrencyFallbacks;
                          CurrencyProvider.showPickerSheet(
                            context,
                            currencies: currencies,
                            selected: selectedCurrency,
                            onSelect: setCurrency,
                          );
                        },
                        tooltip: 'Currency',
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        onPressed: _refresh,
                        tooltip: t('refresh_label'),
                      ),
                    ],
                  ),
                ),

                // ── Scrollable body ───────────────────────────────────
                Expanded(child: _error != null
                    ? errorStateWidget(context, _error!, _refresh)
                    : RefreshIndicator(
                  onRefresh: _refresh,
                  color: AppColors.cyan,
                  child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                // Group header card
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                            color: _groupColor.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _isCreator ? _pickGroupImage : null,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: _groupColor,
                                backgroundImage: (_group['groupImageUrl'] != null &&
                                        _group['groupImageUrl'].toString().isNotEmpty)
                                    ? NetworkImage(_group['groupImageUrl'].toString())
                                    : null,
                                child: _uploadingImage
                                    ? const SizedBox(
                                        width: 20, height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : (_group['groupImageUrl'] != null &&
                                            _group['groupImageUrl'].toString().isNotEmpty)
                                        ? null
                                        : Text(
                                            title.isNotEmpty ? title[0].toUpperCase() : '?',
                                            style: const TextStyle(
                                                fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                              ),
                              if (_isCreator && !_uploadingImage)
                                Positioned(
                                  right: 0, bottom: 0,
                                  child: Container(
                                    width: 18, height: 18,
                                    decoration: BoxDecoration(
                                      color: AppColors.cyan,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 1.5),
                                    ),
                                    child: const Icon(Icons.camera_alt_rounded, size: 10, color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: AppThemeColors.primaryText(context)),
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(
                                t('by_creator_label').replaceFirst('{creator}', _emailOf(_group['creator'])),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppThemeColors.mutedText(context)),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_isCreator)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _groupColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(t('you_are_the_creator_label'),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: _groupColor,
                                          fontWeight: FontWeight.w600)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Horizontal Scrollable Service Bar ──────────────
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      if ((_group['description'] ?? '').toString().isNotEmpty)
                        _serviceChip(
                          icon: Icons.info_outline_rounded,
                          label: 'Description',
                          color: const Color(0xFF00695C),
                          onTap: () => _showDescriptionSheet(context, t),
                        ),
                      _serviceChip(
                        icon: Icons.people_alt_rounded,
                        label: t('members_label'),
                        color: const Color(0xFF1565C0),
                        badge: activeMembers,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupMembersPage(
                                groupId: widget.groupId,
                                groupTitle: title,
                                isCreator: _isCreator,
                                userEmail: _userEmail ?? '',
                                creatorEmail: _emailOf(_group['creator']),
                                initialMembers: members,
                                initialPendingInvites: List<dynamic>.from(_group['pendingInvites'] ?? []),
                                initialDeclinedInvites: List<dynamic>.from(_group['declinedInvites'] ?? []),
                              ),
                            ),
                          );
                          _refresh();
                        },
                      ),
                      _serviceChip(
                        icon: Icons.receipt_long_rounded,
                        label: t('expenses_label'),
                        color: const Color(0xFF2E7D32),
                        badge: expenses.length,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupExpensesPage(
                                groupId: widget.groupId,
                                groupTitle: title,
                                isCreator: _isCreator,
                                userEmail: _userEmail ?? '',
                                initialExpenses: expenses,
                                initialMembers: members,
                                initialMemberPayments: List<dynamic>.from(_group['memberPayments'] ?? []),
                              ),
                            ),
                          );
                          _refresh();
                        },
                      ),
                      _serviceChip(
                        icon: Icons.add_circle_rounded,
                        label: t('add_expense_label'),
                        color: const Color(0xFF00838F),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupExpensesPage(
                                groupId: widget.groupId,
                                groupTitle: title,
                                isCreator: _isCreator,
                                userEmail: _userEmail ?? '',
                                initialExpenses: expenses,
                                initialMembers: members,
                                initialMemberPayments: List<dynamic>.from(_group['memberPayments'] ?? []),
                                openAddExpense: true,
                              ),
                            ),
                          );
                          _refresh();
                        },
                      ),
                      _serviceChip(
                        icon: Icons.person_add_alt_1_rounded,
                        label: t('add_member_label'),
                        color: const Color(0xFF6A1B9A),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupMembersPage(
                                groupId: widget.groupId,
                                groupTitle: title,
                                isCreator: _isCreator,
                                userEmail: _userEmail ?? '',
                                creatorEmail: _emailOf(_group['creator']),
                                initialMembers: members,
                                initialPendingInvites: List<dynamic>.from(_group['pendingInvites'] ?? []),
                                initialDeclinedInvites: List<dynamic>.from(_group['declinedInvites'] ?? []),
                                openAddMember: true,
                              ),
                            ),
                          );
                          _refresh();
                        },
                      ),
                      _serviceChip(
                        icon: Icons.bar_chart_rounded,
                        label: t('stats_label'),
                        color: const Color(0xFF1565C0),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupStatsPage(
                                groupId: widget.groupId,
                                groupTitle: title,
                              ),
                            ),
                          );
                        },
                      ),
                      _serviceChip(
                        icon: Icons.groups_rounded,
                        label: t('communities_title'),
                        color: const Color(0xFF0277BD),
                        badge: _communities.isNotEmpty ? _communities.length : null,
                        onTap: _showCommunitiesSheet,
                      ),
                      _serviceChip(
                        icon: Icons.send_to_mobile_rounded,
                        label: 'Request Payment',
                        color: const Color(0xFFE65100),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupRequestPaymentPage(
                                groupId: widget.groupId,
                                groupTitle: title,
                                groupColor: _groupColor,
                                initialGroup: _group,
                                userEmail: _userEmail ?? '',
                              ),
                            ),
                          );
                        },
                      ),
                      _serviceChip(
                        icon: Icons.payment_rounded,
                        label: 'Process Payment',
                        color: const Color(0xFF00695C),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupProcessPaymentPage(
                                groupId: widget.groupId,
                                groupTitle: title,
                                groupColor: _groupColor,
                                initialGroup: _group,
                                userEmail: _userEmail ?? '',
                              ),
                            ),
                          );
                          _refresh();
                        },
                      ),
                      if (_isCreator)
                        _serviceChip(
                          icon: Icons.link_rounded,
                          label: t('invite_label'),
                          color: const Color(0xFF00796B),
                          onTap: () => _showInviteSheet(context, t),
                        ),
                      if (_isCreator)
                        _serviceChip(
                          icon: Icons.color_lens_rounded,
                          label: t('color_label'),
                          color: _groupColor,
                          onTap: _updateColor,
                        ),
                      if (!_isCreator)
                        _serviceChip(
                          icon: Icons.exit_to_app_rounded,
                          label: t('leave_label'),
                          color: Colors.orange.shade700,
                          onTap: _confirmLeave,
                        ),
                      if (_isCreator)
                        _serviceChip(
                          icon: Icons.delete_rounded,
                          label: t('delete'),
                          color: const Color(0xFFD32F2F),
                          onTap: _confirmDeleteGroup,
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Horizontal Stats Row ─────────────────────────────
                SizedBox(
                  height: 140,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _statCard(
                          '$activeMembers', t('members_label'),
                          Icons.people_rounded,
                          const Color(0xFF1565C0)),
                      _statCard(
                          '${expenses.length}', t('expenses_label'),
                          Icons.receipt_rounded,
                          const Color(0xFF2E7D32)),
                      _statCard(
                          '${members.where((m) => m['leftAt'] != null).length}',
                          t('left_label'),
                          Icons.person_off_rounded,
                          Colors.orange),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Communities strip ────────────────────────────────
                if (_communities.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      const Icon(Icons.groups_rounded, size: 15, color: AppColors.cyan),
                      const SizedBox(width: 6),
                      Text(t('communities_title'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.cyan)),
                      const Spacer(),
                      GestureDetector(
                        onTap: _showCommunitiesSheet,
                        child: Text(t('manage_communities_link'), style: const TextStyle(fontSize: 11, color: AppColors.cyan, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _communities.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final c = _communities[i];
                        final cName = (c['name'] ?? 'Community').toString();
                        final cColor = _parseCommunityColor(c['color']);
                        return GestureDetector(
                          onTap: _showCommunitiesSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: cColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: cColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Container(width: 16, height: 16,
                                decoration: BoxDecoration(color: cColor, shape: BoxShape.circle),
                                child: Center(child: Text(cName.isNotEmpty ? cName[0].toUpperCase() : 'C',
                                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)))),
                              const SizedBox(width: 6),
                              Text(cName, style: TextStyle(color: cColor, fontWeight: FontWeight.w700, fontSize: 12)),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Who Owes What ────────────────────────────────────
                Builder(builder: (context) {
                  final balances = _computeBalances();
                  if (balances.isEmpty) return const SizedBox.shrink();
                  // Notes-page pastel palette, rotated by card index
                  const _owePastels = [
                    Color(0xFFFFF4E6), // cream
                    Color(0xFFE8F5E9), // light green
                    Color(0xFFFCE4EC), // light pink
                    Color(0xFFE3F2FD), // light blue
                    Color(0xFFFFF9C4), // light yellow
                    Color(0xFFF3E5F5), // light purple
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF8000).withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFFF8000), size: 18),
                          ),
                          const SizedBox(width: 8),
                          Text(t('who_owes_what_title'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                      const SizedBox(height: 10),
                      Builder(builder: (ctx) {
                        final debts = _computePairwiseDebts(balances);
                        final myEmail = (_userEmail ?? '').toLowerCase();
                        final entries = balances.entries.toList();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Net balance cards ──────────────────────
                            SizedBox(
                              height: 148,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: entries.length,
                                itemBuilder: (_, idx) {
                                  final entry = entries[idx];
                                  final memberEmail = entry.key;
                                  final net = entry.value;
                                  final isMe = memberEmail.toLowerCase() == myEmail;
                                  final isOwes = net > 0;
                                  final amtColor = isOwes ? const Color(0xFFD32F2F) : const Color(0xFF2E7D32);
                                  final shortName = memberEmail.split('@').first;
                                  final bg = _owePastels[idx % _owePastels.length];
                                  // Find who this person pays (first match in debts)
                                  final myDebt = isMe && isOwes
                                      ? debts.firstWhere(
                                          (d) => (d['from'] as String).toLowerCase() == myEmail,
                                          orElse: () => <String, dynamic>{},
                                        )
                                      : <String, dynamic>{};
                                  final payTo = myDebt['to'] as String?;
                                  final payAmt = myDebt['amount'] as double?;
                                  return _tricolorBorderBox(
                                    margin: const EdgeInsets.only(right: 10),
                                    radius: 16,
                                    child: Container(
                                      width: 140,
                                      color: bg,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            isMe ? t('you_label') : shortName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            isOwes ? t('owes_label') : t('is_owed_label'),
                                            style: TextStyle(fontSize: 11, color: amtColor, fontWeight: FontWeight.w500),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            formatAmount(net.abs(), from: 'INR'),
                                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: amtColor),
                                          ),
                                          if (isMe && isOwes && payTo != null) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              '→ ${payTo.split('@').first}',
                                              style: const TextStyle(fontSize: 10, color: AppColors.cyan, fontWeight: FontWeight.w600),
                                              maxLines: 1, overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 6),
                                            SizedBox(
                                              width: double.infinity,
                                              height: 26,
                                              child: ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.cyan,
                                                  padding: EdgeInsets.zero,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                  elevation: 0,
                                                ),
                                                onPressed: () {
                                                  final toAddr = payTo;
                                                  final toAmt = payAmt ?? net.abs();
                                                  LendenPaymentHelper.showPaymentSheet(
                                                    ctx,
                                                    counterpartyEmail: toAddr,
                                                    amount: toAmt,
                                                    description: t('group_expense_repayment_label'),
                                                    payEndpoint: '/api/group-transactions/${widget.groupId}/record-payment',
                                                    payBody: {'toEmail': toAddr, 'amount': toAmt},
                                                    onSuccess: () {
                                                      _refresh();
                                                      _showGroupPaymentSuccess(ctx, toAddr, toAmt);
                                                    },
                                                  );
                                                },
                                                child: Text(t('pay_now_label'), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            // ── Settlement plan ────────────────────────
                            if (debts.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(children: [
                                  const Icon(Icons.swap_horiz_rounded, size: 15, color: AppColors.cyan),
                                  const SizedBox(width: 6),
                                  Text(t('how_to_settle_label'),
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.cyan)),
                                ]),
                              ),
                              const SizedBox(height: 8),
                              ...debts.map((d) {
                                final from = d['from'] as String;
                                final to = d['to'] as String;
                                final amt = d['amount'] as double;
                                final fromMe = from.toLowerCase() == myEmail;
                                final fromShort = fromMe ? t('you_label') : from.split('@').first;
                                final toShort = to.split('@').first;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                                  child: _tricolorBorderBox(
                                    radius: 12,
                                    borderWidth: 1.5,
                                    child: Container(
                                      color: fromMe ? const Color(0xFFE3F2FD) : Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor: fromMe
                                                ? AppColors.cyan
                                                : Colors.grey[300],
                                            child: Text(
                                              fromShort[0].toUpperCase(),
                                              style: TextStyle(
                                                color: fromMe ? Colors.white : Colors.grey[700],
                                                fontSize: 12, fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: RichText(
                                              text: TextSpan(
                                                style: TextStyle(fontSize: 13, color: AppThemeColors.primaryText(context)),
                                                children: [
                                                  TextSpan(
                                                    text: fromShort,
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      color: fromMe ? AppColors.cyan : AppThemeColors.primaryText(context),
                                                    ),
                                                  ),
                                                  TextSpan(text: ' ${t('pays_label')} '),
                                                  TextSpan(
                                                    text: toShort,
                                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            formatAmount(amt, from: 'INR'),
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: fromMe ? const Color(0xFFD32F2F) : Colors.grey[700],
                                            ),
                                          ),
                                          if (fromMe) ...[
                                            const SizedBox(width: 8),
                                            SizedBox(
                                              height: 28,
                                              child: ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.cyan,
                                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                  elevation: 0,
                                                ),
                                                onPressed: () => LendenPaymentHelper.showPaymentSheet(
                                                  ctx,
                                                  counterpartyEmail: to,
                                                  amount: amt,
                                                  description: t('group_expense_repayment_label'),
                                                  payEndpoint: '/api/group-transactions/${widget.groupId}/record-payment',
                                                  payBody: {'toEmail': to, 'amount': amt},
                                                  onSuccess: () {
                                                    _refresh();
                                                    _showGroupPaymentSuccess(ctx, to, amt);
                                                  },
                                                ),
                                                child: Text(t('pay_label'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ],
                        );
                      }),
                      const SizedBox(height: 16),
                    ],
                  );
                }),

                // ── Recent Expenses Preview ──────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(t('recent_expenses_label'),
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupExpensesPage(
                                groupId: widget.groupId,
                                groupTitle: title,
                                isCreator: _isCreator,
                                userEmail: _userEmail ?? '',
                                initialExpenses: expenses,
                                initialMembers: members,
                                initialMemberPayments: List<dynamic>.from(_group['memberPayments'] ?? []),
                              ),
                            ),
                          );
                          _refresh();
                        },
                        child: Text('${t('see_all_label')} →',
                            style:
                                const TextStyle(color: AppColors.cyan)),
                      ),
                    ],
                  ),
                ),

                if (expenses.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long,
                              color: AppThemeColors.mutedText(context), size: 64),
                          const SizedBox(height: 8),
                          Text(t('no_expenses_yet_label'),
                              style: TextStyle(color: AppThemeColors.mutedText(context))),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: expenses.length > 5 ? 5 : expenses.length,
                          itemBuilder: (_, i) {
                            final e = expenses[i]
                                as Map<String, dynamic>;
                            final amount =
                                (e['amount'] ?? 0).toString();
                            final currency =
                                e['currency'] ?? 'INR';
                            final currencySymbol = currencySymbolFor(currency.toString());
                            return _tricolorBorderBox(
                              margin: const EdgeInsets.only(bottom: 10),
                              radius: 16,
                              child: Container(
                              color: _kCardColors[i % _kCardColors.length],
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2E7D32)
                                          .withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                        Icons.receipt_outlined,
                                        color: Color(0xFF2E7D32),
                                        size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e['description'] ?? '-',
                                          style: const TextStyle(
                                              fontWeight:
                                                  FontWeight.w600,
                                              fontSize: 14),
                                          overflow:
                                              TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          t('by_creator_label').replaceFirst('{creator}', _resolveEmail(e['addedBy'])),
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[500]),
                                          overflow:
                                              TextOverflow.ellipsis,
                                        ),
                                        if ((e['createdAt'] ?? e['date']) != null) ...[
                                          const SizedBox(height: 2),
                                          Row(children: [
                                            Icon(Icons.access_time_rounded,
                                                size: 11,
                                                color: Colors.grey[400]),
                                            const SizedBox(width: 3),
                                            Flexible(
                                              child: Text(
                                                _fmtDt(e['createdAt'] ?? e['date']),
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[400]),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ]),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '$currencySymbol$amount',
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF2E7D32)),
                                  ),
                                ],
                              ),
                            ),
                          );
                          },
                    ),
                const SizedBox(height: 24),
              ]))))  // closes Column.children + Column + SCView + RefreshIndicator + Expanded
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.7);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.85,
        size.width * 0.5, size.height * 0.7);
    path.quadraticBezierTo(size.width * 0.75, size.height * 0.55,
        size.width, size.height * 0.7);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> old) => false;
}
