import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import '../../utils/image_picker_utils.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/wave_widget.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/transaction_constants.dart';
import '../../session.dart';

class CreateCommunityPage extends StatefulWidget {
  const CreateCommunityPage({Key? key}) : super(key: key);

  @override
  State<CreateCommunityPage> createState() => _CreateCommunityPageState();
}

class _CreateCommunityPageState extends State<CreateCommunityPage> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  Color _color = const Color(0xFF00B4D8);
  Uint8List? _imageBytes;
  bool _creating = false;
  String? _error;
  String _category = 'other';

  // Community limit info
  int _limit = 1;
  int _count = 0;
  bool _overLimit = false;
  bool _hasSubscription = false;
  int _coinCost = 30;
  int _userCoins = 0;

  // Initial members to add after creation
  List<String> _memberEmails = [];
  List<Map<String, dynamic>> _friends = [];
  bool _loadingFriends = false;
  List<Map<String, dynamic>> _counterparties = [];
  bool _loadingCounterparties = false;
  List<Map<String, dynamic>> _userGroups = [];
  bool _loadingGroups = false;

  @override
  void initState() {
    super.initState();
    _loadLimitInfo();
  }

  Future<void> _loadLimitInfo() async {
    try {
      final res = await ApiClient.get('/api/communities/limit-info');
      if (res.statusCode == 200 && mounted) {
        final d = jsonDecode(res.body);
        setState(() {
          _limit = d['limit'] ?? 1;
          _count = d['count'] ?? 0;
          _overLimit = d['overLimit'] ?? false;
          _hasSubscription = d['hasSubscription'] ?? false;
          _coinCost = d['cost'] ?? 30;
          _userCoins = d['userCoins'] ?? 0;
        });
      }
    } catch (_) {}
  }

  static const List<Color> _presetColors = [
    Color(0xFF00B4D8), Color(0xFF0096C7), Color(0xFF023E8A), Color(0xFF2196F3),
    Color(0xFF3F51B5), Color(0xFF673AB7), Color(0xFF9C27B0), Color(0xFFE91E63),
    Color(0xFFF44336), Color(0xFFFF5722), Color(0xFFFF9800), Color(0xFFFFC107),
    Color(0xFF4CAF50), Color(0xFF009688), Color(0xFF8BC34A), Color(0xFF607D8B),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String get _colorHex => '#${_color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  Future<void> _pickImage() async {
    final result = await ImagePickerUtils.pickWithSheet(context);
    if (result != null && mounted) {
      setState(() { _imageBytes = result.bytes; });
    }
  }

  Future<void> _pickColor() async {
    Color temp = _color;
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
          padding: EdgeInsets.fromLTRB(24, 20, 24, 32 + MediaQuery.of(ctx).padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // drag handle
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),

            // Header
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: temp.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.palette_rounded, color: temp, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AppLocalizations.of(ctx).t('pick_community_color_title'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(ctx))),
                Text(AppLocalizations.of(ctx).t('pick_community_color_desc'),
                  style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
              ])),
              // Selected color preview
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: temp,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: temp.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2))],
                  border: Border.all(color: AppThemeColors.border(ctx), width: 2),
                ),
              ),
            ]),

            const SizedBox(height: 20),

            // Preset color grid
            Text('PRESETS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: AppThemeColors.mutedText(ctx), letterSpacing: 1.4)),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8, crossAxisSpacing: 10, mainAxisSpacing: 10,
              ),
              itemCount: _presetColors.length,
              itemBuilder: (_, i) {
                final c = _presetColors[i];
                final selected = temp.toARGB32() == c.toARGB32();
                return GestureDetector(
                  onTap: () => setSheet(() => temp = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.white : Colors.transparent,
                        width: selected ? 2.5 : 0,
                      ),
                      boxShadow: selected
                          ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 8, offset: const Offset(0, 2))]
                          : [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)],
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                        : null,
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // Custom color row
            GestureDetector(
              onTap: () async {
                Color custom = temp;
                final picked = await showDialog<Color>(
                  context: ctx,
                  builder: (dCtx) => AlertDialog(
                    backgroundColor: AppThemeColors.cardBg(dCtx),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: Text(AppLocalizations.of(dCtx).t('custom_color_label'), style: TextStyle(color: AppThemeColors.primaryText(dCtx), fontWeight: FontWeight.bold)),
                    content: SingleChildScrollView(
                      child: ColorPicker(
                        pickerColor: custom,
                        onColorChanged: (c) => custom = c,
                        pickerAreaHeightPercent: 0.65,
                        enableAlpha: false,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx),
                        child: Text(AppLocalizations.of(dCtx).t('cancel'), style: TextStyle(color: AppThemeColors.secondaryText(dCtx))),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(dCtx, custom),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        child: Text(AppLocalizations.of(dCtx).t('select')),
                      ),
                    ],
                  ),
                );
                if (picked != null) setSheet(() => temp = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppThemeColors.surfaceBg(ctx),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppThemeColors.border(ctx)),
                ),
                child: Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: AppThemeColors.border(ctx),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.colorize_rounded, size: 17, color: AppThemeColors.secondaryText(ctx)),
                  ),
                  const SizedBox(width: 12),
                  Text(AppLocalizations.of(ctx).t('custom_color_row'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: AppThemeColors.primaryText(ctx))),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded, color: AppThemeColors.mutedText(ctx), size: 20),
                ]),
              ),
            ),

            const SizedBox(height: 20),

            // Apply button
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: temp,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: temp.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _color = temp);
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0,
                ),
                child: Text(AppLocalizations.of(ctx).t('apply_color_btn'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _loadFriends() async {
    if (_loadingFriends) return;
    setState(() => _loadingFriends = true);
    try {
      final res = await ApiClient.get('/api/friends');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _friends = List<Map<String, dynamic>>.from(data['friends'] ?? []));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingFriends = false);
  }

  Future<void> _loadCounterparties() async {
    if (_loadingCounterparties) return;
    setState(() => _loadingCounterparties = true);
    try {
      final session = Provider.of<SessionProvider>(context, listen: false);
      final email = Uri.encodeComponent(session.user?['email']?.toString() ?? '');
      final res = await ApiClient.get('/api/counterparties/user?email=$email');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _counterparties = List<Map<String, dynamic>>.from(data['counterparties'] ?? []));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingCounterparties = false);
  }

  Future<void> _loadGroups() async {
    if (_loadingGroups || _userGroups.isNotEmpty) return;
    setState(() => _loadingGroups = true);
    try {
      final res = await ApiClient.get('/api/group-transactions/user-groups');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _userGroups = List<Map<String, dynamic>>.from(data['groups'] ?? []));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingGroups = false);
  }

  // Generic flat picker for people — returns selected emails.
  Future<List<String>> _showCommPeoplePicker({
    required String title,
    required IconData icon,
    required List<Map<String, dynamic>> people,
  }) async {
    final List<String> picked = [];
    String search = '';
    final myEmail = Provider.of<SessionProvider>(context, listen: false).user?['email']?.toString().toLowerCase() ?? '';
    final available = people.where((p) {
      final e = (p['email'] ?? '').toString().toLowerCase();
      return e.isNotEmpty && e != myEmail && !_memberEmails.map((x) => x.toLowerCase()).contains(e);
    }).toList();

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final filtered = available.where((p) {
            if (search.isEmpty) return true;
            final e = (p['email'] ?? '').toString().toLowerCase();
            final n = (p['name'] ?? p['username'] ?? '').toString().toLowerCase();
            return e.contains(search.toLowerCase()) || n.contains(search.toLowerCase());
          }).toList();
          final allSel = filtered.isNotEmpty && filtered.every((p) => picked.contains((p['email'] ?? '').toString()));
          return DraggableScrollableSheet(
            initialChildSize: 0.82, minChildSize: 0.5, maxChildSize: 0.95,
            builder: (_, sc) => Container(
              decoration: BoxDecoration(color: AppThemeColors.cardBg(ctx), borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
              child: Column(children: [
                const SizedBox(height: 12),
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
                  Container(padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]), borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, color: Colors.white, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx)))),
                  if (picked.isNotEmpty)
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text('${picked.length} selected', style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w600))),
                  const SizedBox(width: 4),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: AppThemeColors.secondaryText(ctx))),
                ])),
                Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 6), child: TextField(
                  onChanged: (v) => setSheet(() => search = v),
                  decoration: InputDecoration(
                    hintText: 'Search by name or email...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true, fillColor: AppThemeColors.surfaceBg(ctx),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                )),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
                  Text('${filtered.length} available', style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(ctx))),
                  const Spacer(),
                  if (filtered.isNotEmpty)
                    TextButton(
                      onPressed: () => setSheet(() {
                        if (allSel) { for (final p in filtered) picked.remove((p['email'] ?? '').toString()); }
                        else { for (final p in filtered) { final e = (p['email'] ?? '').toString(); if (e.isNotEmpty && !picked.contains(e)) picked.add(e); } }
                      }),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: Text(allSel ? 'Deselect All' : 'Select All', style: const TextStyle(color: AppColors.cyan, fontSize: 12)),
                    ),
                ])),
                Expanded(
                  child: filtered.isEmpty
                    ? Center(child: Text('No people available', style: TextStyle(color: AppThemeColors.mutedText(ctx))))
                    : ListView.separated(
                        controller: sc,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: AppThemeColors.divider(ctx)),
                        itemBuilder: (_, i) {
                          final p = filtered[i];
                          final email = (p['email'] ?? '').toString();
                          final name = (p['name'] ?? p['username'] ?? '').toString();
                          final isSel = picked.contains(email);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            leading: CircleAvatar(backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                              child: Text(name.isNotEmpty ? name[0].toUpperCase() : email[0].toUpperCase(),
                                style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold))),
                            title: Text(name.isNotEmpty ? name : email, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(ctx))),
                            subtitle: name.isNotEmpty ? Text(email, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))) : null,
                            trailing: Checkbox(value: isSel, activeColor: AppColors.cyan,
                              onChanged: (_) => setSheet(() { if (isSel) picked.remove(email); else picked.add(email); })),
                            onTap: () => setSheet(() { if (isSel) picked.remove(email); else picked.add(email); }),
                          );
                        },
                      ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 4),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(picked.isEmpty ? 'Done' : 'Add ${picked.length} Member${picked.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
    return picked;
  }

  Future<List<String>> _showGroupMemberPicker() async {
    final List<String> picked = [];
    int selectedGroupIdx = -1;
    List<Map<String, dynamic>> groupMembers = [];
    bool loadingMembers = false;
    String search = '';
    final myEmail = Provider.of<SessionProvider>(context, listen: false).user?['email']?.toString().toLowerCase() ?? '';

    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final filteredGroups = _userGroups.where((g) {
            if (search.isEmpty || selectedGroupIdx != -1) return true;
            return (g['title'] ?? '').toString().toLowerCase().contains(search.toLowerCase());
          }).toList();
          final filteredMembers = selectedGroupIdx == -1 ? <Map<String, dynamic>>[] : groupMembers.where((m) {
            if (search.isEmpty) return true;
            final e = (m['email'] ?? '').toString().toLowerCase();
            final n = (m['name'] ?? '').toString().toLowerCase();
            return e.contains(search.toLowerCase()) || n.contains(search.toLowerCase());
          }).toList();
          return DraggableScrollableSheet(
            initialChildSize: 0.82, minChildSize: 0.5, maxChildSize: 0.95,
            builder: (_, sc) => Container(
              decoration: BoxDecoration(color: AppThemeColors.cardBg(ctx), borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
              child: Column(children: [
                const SizedBox(height: 12),
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
                  Container(padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.group_work_rounded, color: AppColors.cyan, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(
                    selectedGroupIdx == -1 ? 'Pick a Group' : (_userGroups[selectedGroupIdx]['title'] ?? 'Group'),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx)))),
                  if (selectedGroupIdx != -1) TextButton(
                    onPressed: () => setSheet(() { selectedGroupIdx = -1; groupMembers = []; search = ''; }),
                    child: const Text('Back', style: TextStyle(color: AppColors.cyan)),
                  ),
                  if (picked.isNotEmpty)
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text('${picked.length} selected', style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w600))),
                  const SizedBox(width: 4),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: AppThemeColors.secondaryText(ctx))),
                ])),
                Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 6), child: TextField(
                  onChanged: (v) => setSheet(() => search = v),
                  decoration: InputDecoration(
                    hintText: selectedGroupIdx == -1 ? 'Search groups...' : 'Search members...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true, fillColor: AppThemeColors.surfaceBg(ctx),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                )),
                Expanded(
                  child: selectedGroupIdx == -1
                    ? (filteredGroups.isEmpty
                        ? Center(child: Text('No groups found', style: TextStyle(color: AppThemeColors.mutedText(ctx))))
                        : ListView.separated(
                            controller: sc,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                            itemCount: filteredGroups.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: AppThemeColors.divider(ctx)),
                            itemBuilder: (_, i) {
                              final g = filteredGroups[i];
                              final realIdx = _userGroups.indexOf(g);
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                leading: CircleAvatar(backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                                  child: Icon(Icons.group_work_rounded, color: AppColors.cyan, size: 18)),
                                title: Text(g['title'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(ctx))),
                                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.cyan),
                                onTap: () async {
                                  setSheet(() { loadingMembers = true; });
                                  final members = List<Map<String, dynamic>>.from(g['members'] ?? []);
                                  final available = members.where((m) {
                                    final e = (m['email'] ?? '').toString().toLowerCase();
                                    return e.isNotEmpty && e != myEmail && m['leftAt'] == null && !_memberEmails.map((x) => x.toLowerCase()).contains(e);
                                  }).toList();
                                  setSheet(() { selectedGroupIdx = realIdx; groupMembers = available; loadingMembers = false; search = ''; });
                                },
                              );
                            },
                          ))
                    : (loadingMembers
                        ? const Center(child: CircularProgressIndicator())
                        : filteredMembers.isEmpty
                            ? Center(child: Text('No new members to add', style: TextStyle(color: AppThemeColors.mutedText(ctx))))
                            : ListView.separated(
                                controller: sc,
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                                itemCount: filteredMembers.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: AppThemeColors.divider(ctx)),
                                itemBuilder: (_, i) {
                                  final m = filteredMembers[i];
                                  final email = (m['email'] ?? '').toString();
                                  final name = (m['name'] ?? '').toString();
                                  final isSel = picked.contains(email);
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    leading: CircleAvatar(backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                                      child: Text(name.isNotEmpty ? name[0].toUpperCase() : email[0].toUpperCase(),
                                        style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold))),
                                    title: Text(name.isNotEmpty ? name : email, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(ctx))),
                                    subtitle: name.isNotEmpty ? Text(email, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))) : null,
                                    trailing: Checkbox(value: isSel, activeColor: AppColors.cyan,
                                      onChanged: (_) => setSheet(() { if (isSel) picked.remove(email); else picked.add(email); })),
                                    onTap: () => setSheet(() { if (isSel) picked.remove(email); else picked.add(email); }),
                                  );
                                },
                              )),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 4),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(picked.isEmpty ? 'Done' : 'Add ${picked.length} Member${picked.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
    return picked;
  }

  Future<void> _showAllSourcesPicker() async {
    if (_loadingFriends || _loadingCounterparties || _loadingGroups) return;
    await _loadFriends();
    if (!mounted) return;
    await _loadCounterparties();
    if (!mounted) return;
    await _loadGroups();
    if (!mounted) return;
    final myEmail = Provider.of<SessionProvider>(context, listen: false).user?['email']?.toString().toLowerCase() ?? '';

    final Set<String> seen = {};
    final List<Map<String, dynamic>> all = [];
    for (final p in [..._friends, ..._counterparties]) {
      final e = (p['email'] ?? '').toString().toLowerCase();
      if (e.isNotEmpty && e != myEmail && !_memberEmails.map((x) => x.toLowerCase()).contains(e) && seen.add(e)) {
        all.add({'email': e, 'name': (p['name'] ?? p['username'] ?? '').toString()});
      }
    }
    for (final g in _userGroups) {
      for (final m in List<Map<String, dynamic>>.from(g['members'] ?? [])) {
        final e = (m['email'] ?? '').toString().toLowerCase();
        if (e.isNotEmpty && e != myEmail && m['leftAt'] == null && !_memberEmails.map((x) => x.toLowerCase()).contains(e) && seen.add(e)) {
          all.add({'email': e, 'name': (m['name'] ?? '').toString()});
        }
      }
    }

    final picked = await _showCommPeoplePicker(title: 'All Sources', icon: Icons.blur_on_rounded, people: all);
    if (picked.isNotEmpty && mounted) {
      setState(() { for (final e in picked) { if (!_memberEmails.contains(e)) _memberEmails.add(e); } });
    }
  }

  Widget _sourceBtn(IconData icon, String label, VoidCallback? onTap, {bool loading = false}) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cyan.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.25)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          loading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan))
            : Icon(icon, color: AppColors.cyan, size: 22),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.cyan, height: 1.2)),
        ]),
      ),
    );
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = AppLocalizations.of(context).t('please_enter_community_name')); return; }

    setState(() { _creating = true; _error = null; });
    try {
      final res = await ApiClient.post('/api/communities', body: {
        'name': name,
        'description': _descCtrl.text.trim(),
        'category': _category,
        'color': _colorHex,
      });
      final data = jsonDecode(res.body);
      if (res.statusCode == 402) {
        final int cost = data['cost'] ?? _coinCost;
        final int coins = data['currentCoins'] ?? _userCoins;
        final t = AppLocalizations.of(context).t;
        setState(() => _error = '${t('not_enough_coins_need')} $cost ${t('not_enough_coins_have')} $coins.');
        return;
      }
      if (res.statusCode == 201) {
        final communityId = data['community']?['_id']?.toString() ?? '';
        if (_imageBytes != null && communityId.isNotEmpty) {
          try {
            await ApiClient.postMultipart(
              '/api/communities/$communityId/image',
              files: [ApiMultipartFile(field: 'image', filename: 'community.jpg', bytes: _imageBytes!)],
            );
          } catch (_) {}
        }
        if (_memberEmails.isNotEmpty && communityId.isNotEmpty) {
          for (final email in _memberEmails) {
            try {
              await ApiClient.post('/api/communities/$communityId/members', body: {'email': email});
            } catch (_) {}
          }
        }
        if (mounted) Navigator.pop(context, data['community']);
      } else {
        setState(() => _error = data['error'] ?? AppLocalizations.of(context).t('failed_to_create_community'));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Widget _field({required IconData icon, required Widget child, Color? iconColor}) {
    final ic = iconColor ?? AppColors.cyan;
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Row(children: [
        const SizedBox(width: 14),
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: ic.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: ic, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(child: child),
        const SizedBox(width: 8),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          // Top wave
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipPath(
              clipper: const DeeperTopWaveClipper(),
              child: Container(
                height: context.sh(70),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppThemeColors.waveGradient(context),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          // Header row
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Row(children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppThemeColors.primaryText(context)),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).t('create_community_btn'),
                    style: TextStyle(
                      color: AppThemeColors.primaryText(context), fontSize: 22,
                      fontWeight: FontWeight.bold, letterSpacing: 0.5,
                    ),
                  ),
                ),
              ]),
            ),
          ),
          // Scrollable content
          Positioned(
            top: 80, left: 0, right: 0, bottom: 0,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue, Color(0xFF7B2FBE)]),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(19)),
              child: Row(children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: Stack(children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        gradient: _imageBytes == null
                            ? LinearGradient(colors: [_color.withValues(alpha: 0.7), _color])
                            : null,
                        borderRadius: BorderRadius.circular(16),
                        image: _imageBytes != null
                            ? DecorationImage(image: MemoryImage(_imageBytes!), fit: BoxFit.cover)
                            : null,
                        boxShadow: [BoxShadow(color: _color.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: _imageBytes == null ? const Icon(Icons.hub_rounded, color: Colors.white, size: 28) : null,
                    ),
                    Positioned(right: 0, bottom: 0,
                      child: Container(
                        width: 18, height: 18,
                        decoration: BoxDecoration(color: AppColors.cyan, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                        child: const Icon(Icons.camera_alt_rounded, size: 10, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppLocalizations.of(context).t('new_community_heading'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context))),
                  const SizedBox(height: 4),
                  Text(AppLocalizations.of(context).t('new_community_subheading'),
                    style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 13)),
                ])),
              ]),
            ),
          ),

          // Coin cost banner when over limit
          if (_overLimit && !_hasSubscription) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Container(width: 34, height: 34,
                  decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.toll_rounded, color: Colors.amber, size: 18)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${AppLocalizations.of(context).t('community_limit_reached')} ($_count/$_limit)',
                    style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w700)),
                  Text('${AppLocalizations.of(context).t('community_coin_cost_desc')} $_coinCost ${AppLocalizations.of(context).t('community_coin_cost_balance')} $_userCoins)',
                    style: const TextStyle(fontSize: 11, color: Colors.amber, height: 1.4)),
                ])),
              ]),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.06),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Container(width: 34, height: 34,
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18)),
                const SizedBox(width: 10),
                Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500))),
                GestureDetector(onTap: () => setState(() => _error = null),
                  child: const Icon(Icons.close_rounded, color: Colors.red, size: 16)),
              ]),
            ),
          ],

          const SizedBox(height: 24),

          // Name
          _field(
            icon: Icons.hub_rounded,
            child: TextField(
              controller: _nameCtrl,
              style: TextStyle(color: AppThemeColors.primaryText(context)),
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).t('community_name_required_label'),
                labelStyle: TextStyle(color: AppThemeColors.secondaryText(context)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Description
          _field(
            icon: Icons.notes_rounded,
            child: TextField(
              controller: _descCtrl,
              maxLines: 2,
              maxLength: 300,
              buildCounter: (ctx, {required currentLength, required isFocused, maxLength}) =>
                  buildDescCounter(ctx, currentLength, maxLength),
              style: TextStyle(color: AppThemeColors.primaryText(context)),
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).t('description_optional_label'),
                labelStyle: TextStyle(color: AppThemeColors.secondaryText(context)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Category
          Text('CATEGORY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppThemeColors.mutedText(context), letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kTxCategories.map((cat) {
              final key = cat['key'] as String;
              final label = cat['label'] as String;
              final icon = cat['icon'] as IconData;
              final color = cat['color'] as Color;
              final selected = _category == key;
              return GestureDetector(
                onTap: () => setState(() => _category = key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? color : color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: selected ? color : color.withValues(alpha: 0.30), width: 1.5),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 14, color: selected ? Colors.white : color),
                    const SizedBox(width: 5),
                    Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : color)),
                  ]),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          // Color picker field
          GestureDetector(
            onTap: _pickColor,
            child: Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppThemeColors.border(context)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                // Icon box tinted with selected color
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: _color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.palette_rounded, color: _color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppLocalizations.of(context).t('community_color_section'), style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context))),
                  const SizedBox(height: 2),
                  Text(_colorHex, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppThemeColors.primaryText(context), letterSpacing: 0.5)),
                ])),
                // Color swatch
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: _color,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: _color.withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(0, 2))],
                    border: Border.all(color: AppThemeColors.border(context), width: 1.5),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: AppThemeColors.mutedText(context), size: 18),
              ]),
            ),
          ),

          const SizedBox(height: 20),

          // Add Initial Members section
          Text('ADD INITIAL MEMBERS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppThemeColors.mutedText(context), letterSpacing: 1.2)),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _sourceBtn(Icons.people_rounded, 'Friends', _loadingFriends ? null : () async {
                await _loadFriends();
                final picked = await _showCommPeoplePicker(title: 'Pick from Friends', icon: Icons.people_rounded, people: _friends);
                if (picked.isNotEmpty && mounted) setState(() { for (final e in picked) { if (!_memberEmails.contains(e)) _memberEmails.add(e); } });
              }, loading: _loadingFriends),
              const SizedBox(width: 8),
              _sourceBtn(Icons.swap_horiz_rounded, 'Counter-\nparties', _loadingCounterparties ? null : () async {
                await _loadCounterparties();
                final picked = await _showCommPeoplePicker(title: 'Pick Counterparties', icon: Icons.swap_horiz_rounded, people: _counterparties);
                if (picked.isNotEmpty && mounted) setState(() { for (final e in picked) { if (!_memberEmails.contains(e)) _memberEmails.add(e); } });
              }, loading: _loadingCounterparties),
              const SizedBox(width: 8),
              _sourceBtn(Icons.group_work_rounded, 'Groups', _loadingGroups ? null : () async {
                await _loadGroups();
                final picked = await _showGroupMemberPicker();
                if (picked.isNotEmpty && mounted) setState(() { for (final e in picked) { if (!_memberEmails.contains(e)) _memberEmails.add(e); } });
              }, loading: _loadingGroups),
              const SizedBox(width: 8),
              _sourceBtn(Icons.blur_on_rounded, 'All\nSources', _showAllSourcesPicker),
            ]),
          ),

          if (_memberEmails.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _memberEmails.map((email) => Chip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                label: Text(email, style: const TextStyle(fontSize: 12)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () => setState(() => _memberEmails.remove(email)),
                backgroundColor: AppColors.cyan.withValues(alpha: 0.10),
                side: BorderSide(color: AppColors.cyan.withValues(alpha: 0.3)),
                labelStyle: TextStyle(color: AppThemeColors.primaryText(context)),
              )).toList(),
            ),
          ],

          const SizedBox(height: 28),

          // Create button
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_color, AppColors.blue]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: _color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: ElevatedButton(
              onPressed: _creating ? null : _create,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _creating
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(AppLocalizations.of(context).t('create_community_btn'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ]),
            ),
          ),
        ],
      ),
    );
  }
}
