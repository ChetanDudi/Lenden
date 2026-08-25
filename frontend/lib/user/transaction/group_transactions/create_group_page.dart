import 'package:elegant_notification/elegant_notification.dart';
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import 'package:share_plus/share_plus.dart';
import '../../../utils/share_utils.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../../widgets/stylish_dialog.dart';
import '../../digitise/gift_card_page.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io' as dart_io;
import '../../../utils/avatar_helpers.dart' as ah;
import '../../../widgets/share_as_note_sheet.dart';
import '../../../api_config.dart';

class CreateGroupPage extends StatefulWidget {
  final List<String>? prefillMemberEmails;
  final bool useCoins;

  const CreateGroupPage({Key? key, this.prefillMemberEmails, this.useCoins = false}) : super(key: key);

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _memberEmailController = TextEditingController();
  List<String> _memberEmails = [];
  Map<String, Map<String, dynamic>> _memberUsers = {};
  List<Map<String, dynamic>> _userGroups = [];
  bool _loadingGroups = false;
  List<Map<String, dynamic>> _userCommunities = [];
  final List<String> _selectedCommunityIds = [];
  final Map<String, String> _selectedCommunityNames = {};
  bool _creatingGroup = false;
  String? _error;
  String? _memberAddError;
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _friendSuggestions = [];
  Set<String> _blockedEmails = {};
  bool _loadingFriends = false;
  XFile? _selectedImage;
  Color? _selectedColor;
  int? _dailyGroupRemaining;

  @override
  void initState() {
    super.initState();
    if (widget.prefillMemberEmails != null) {
      _memberEmails = List<String>.from(widget.prefillMemberEmails!);
    }
    _memberEmailController.addListener(_updateFriendSuggestions);
    _loadFriends();
    _loadDailyLimits();
    _loadCommunities();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<SessionProvider>(context, listen: false).loadFreebieCounts();
      }
    });
  }

  @override
  void dispose() {
    _memberEmailController.removeListener(_updateFriendSuggestions);
    _titleController.dispose();
    _descriptionController.dispose();
    _memberEmailController.dispose();
    super.dispose();
  }

  Color _noteColor(int index) {
    const colors = [
      Color(0xFFFFF4E6), Color(0xFFE8F5E9), Color(0xFFFCE4EC),
      Color(0xFFE3F2FD), Color(0xFFFFF9C4), Color(0xFFF3E5F5),
    ];
    return colors[index % colors.length];
  }

  Future<void> _loadCommunities() async {
    try {
      final res = await ApiClient.get('/api/communities');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _userCommunities = List<Map<String, dynamic>>.from(data['communities'] ?? []));
      }
    } catch (_) {}
  }

  Future<void> _showCommunityPicker() async {
    Color parseColor(dynamic c) {
      try {
        if (c is String && c.startsWith('#')) return Color(int.parse('FF${c.replaceFirst('#', '')}', radix: 16));
      } catch (_) {}
      return AppColors.cyan;
    }

    // Work on a local copy so we can cancel
    final tempSelected = Set<String>.from(_selectedCommunityIds);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, scrollCtrl) => Container(
            decoration: BoxDecoration(color: AppThemeColors.cardBg(ctx), borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
            child: Column(children: [
              const SizedBox(height: 12),
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.hub_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Add to Communities', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
                    Text('Select one or more (optional)', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
                  ])),
                  if (tempSelected.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text('${tempSelected.length} selected', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.cyan)),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: AppThemeColors.divider(ctx)),
              Expanded(
                child: _userCommunities.isEmpty
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 56, height: 56, decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(18)),
                            child: const Icon(Icons.hub_rounded, size: 28, color: AppColors.cyan)),
                          const SizedBox(height: 12),
                          Text('No communities yet', style: TextStyle(fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
                          Text('Create a community after making this group to organize them together.',
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx), height: 1.5)),
                        ]),
                      ))
                    : ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: _userCommunities.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final c = _userCommunities[i];
                          final id = (c['_id'] ?? '').toString();
                          final name = (c['name'] ?? '').toString();
                          final color = parseColor(c['color']);
                          final grpCount = (c['groups'] as List?)?.length ?? 0;
                          final initials = name.isNotEmpty ? name[0].toUpperCase() : 'C';
                          final isSelected = tempSelected.contains(id);
                          return GestureDetector(
                            onTap: () => setSheet(() {
                              if (isSelected) tempSelected.remove(id);
                              else tempSelected.add(id);
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? color.withValues(alpha: 0.08) : AppThemeColors.surfaceBg(ctx),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: isSelected ? color.withValues(alpha: 0.5) : AppThemeColors.border(ctx), width: isSelected ? 1.5 : 1),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                                  child: Center(child: Text(initials, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 17))),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppThemeColors.primaryText(ctx))),
                                  Text('$grpCount group${grpCount == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
                                ])),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 150),
                                  child: isSelected
                                      ? Icon(Icons.check_circle_rounded, key: const ValueKey(true), color: color, size: 22)
                                      : Icon(Icons.radio_button_unchecked_rounded, key: const ValueKey(false),
                                          color: AppThemeColors.border(ctx), size: 22),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
              // Done button
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(ctx).padding.bottom),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                      minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
                    onPressed: () {
                      setState(() {
                        _selectedCommunityIds
                          ..clear()
                          ..addAll(tempSelected);
                        _selectedCommunityNames.clear();
                        for (final c in _userCommunities) {
                          final id = (c['_id'] ?? '').toString();
                          if (_selectedCommunityIds.contains(id)) {
                            _selectedCommunityNames[id] = (c['name'] ?? '').toString();
                          }
                        }
                      });
                      Navigator.pop(ctx);
                    },
                    child: Text(
                      tempSelected.isEmpty ? 'No Community' : 'Done — ${tempSelected.length} selected',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _loadFriends() async {
    try {
      final res = await ApiClient.get('/api/friends');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (!mounted) return;
        setState(() {
          _friends = List<Map<String, dynamic>>.from(data['friends'] ?? []);
          final blocked = List<Map<String, dynamic>>.from(data['blockedUsers'] ?? []);
          _blockedEmails = blocked
              .map((u) => (u['email'] ?? '').toString().toLowerCase().trim())
              .where((e) => e.isNotEmpty)
              .toSet();
        });
        _updateFriendSuggestions();
      }
    } catch (_) {}
  }

  Future<void> _loadDailyLimits() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.hasFeature('group_creation')) return;
    try {
      final res = await ApiClient.get('/api/limits/daily');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _dailyGroupRemaining = data['limits']?['groupCreations']?['remaining'];
        });
      }
    } catch (_) {}
  }

  bool _isBlocked(String? email) {
    final t = email?.toLowerCase().trim();
    return t != null && t.isNotEmpty && _blockedEmails.contains(t);
  }

  bool _hasBlockedMembers() => _memberEmails.any(_isBlocked);

  void _updateFriendSuggestions() {
    final query = _memberEmailController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _friendSuggestions = []);
      return;
    }
    final matches = _friends.where((f) {
      final email = (f['email'] ?? '').toString().toLowerCase();
      final name = (f['name'] ?? f['username'] ?? '').toString().toLowerCase();
      if (_isBlocked(email)) return false;
      return email.contains(query) || name.contains(query);
    }).toList();
    setState(() => _friendSuggestions = matches.take(5).toList());
  }

  Future<bool> _userExists(String email) async {
    try {
      final res = await ApiClient.post('/api/users/check-email', body: {'email': email});
      if (res.statusCode == 200) {
        return json.decode(res.body)['unique'] == false;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _addMemberEmail() async {
    final t = AppLocalizations.of(context).t;
    final email = _memberEmailController.text.trim();
    if (email.isEmpty) return;
    setState(() => _memberAddError = null);

    final currentEmail =
        Provider.of<SessionProvider>(context, listen: false).user?['email'];
    if (email.toLowerCase() == (currentEmail ?? '').toLowerCase()) {
      setState(() {
        _memberAddError = t('creator_already_added_by_default');
        _memberEmailController.clear();
      });
      return;
    }
    if (_isBlocked(email)) {
      showBlockedUserDialog(context);
      return;
    }
    if (_memberEmails.contains(email)) {
      setState(() {
        _memberAddError = t('user_already_added_to_group');
        _memberEmailController.clear();
      });
      return;
    }
    final exists = await _userExists(email);
    if (!exists) {
      setState(() => _memberAddError = t('user_does_not_exist_cant_add'));
      return;
    }
    final matchedFriend = _friends.firstWhere(
      (f) => (f['email'] ?? '').toString().toLowerCase() == email.toLowerCase(),
      orElse: () => {},
    );
    setState(() {
      _memberEmails.add(email);
      _memberEmailController.clear();
      if (matchedFriend.isNotEmpty) {
        _memberUsers[email] = {
          '_id': (matchedFriend['_id'] ?? '').toString(),
          'name': (matchedFriend['name'] ?? matchedFriend['username'] ?? '').toString(),
        };
      }
    });
  }

  void _removeMemberEmail(String email) {
    setState(() {
      _memberEmails.remove(email);
      _memberUsers.remove(email);
    });
  }

  Future<void> _addMembersFromFriends() async {
    final t = AppLocalizations.of(context).t;
    List<Map<String, dynamic>> allFriends;
    if (_friends.isNotEmpty) {
      allFriends = _friends;
    } else {
      setState(() => _loadingFriends = true);
      try {
        final res = await ApiClient.get('/api/friends');
        if (!mounted) return;
        if (res.statusCode != 200) { setState(() => _loadingFriends = false); return; }
        final data = jsonDecode(res.body);
        allFriends = List<Map<String, dynamic>>.from(data['friends'] ?? []);
        final blocked = List<Map<String, dynamic>>.from(data['blockedUsers'] ?? []);
        _blockedEmails = blocked
            .map((u) => (u['email'] ?? '').toString().toLowerCase().trim())
            .where((e) => e.isNotEmpty)
            .toSet();
        if (mounted) setState(() { _friends = allFriends; _loadingFriends = false; });
      } catch (_) {
        if (mounted) setState(() => _loadingFriends = false);
        return;
      }
    }
    if (!mounted) return;

    final tempSelected = Set<String>.from(_memberEmails);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = allFriends.where((f) {
              final email = (f['email'] ?? '').toString().toLowerCase();
              final name = (f['name'] ?? f['username'] ?? '').toString().toLowerCase();
              final q = searchQuery.toLowerCase();
              return q.isEmpty || email.contains(q) || name.contains(q);
            }).toList();
            final selectableCount = allFriends.where((f) => !_isBlocked((f['email'] ?? '').toString())).length;
            final allSelected = tempSelected.length >= selectableCount && selectableCount > 0;

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              builder: (_, scrollController) => Container(
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(ctx),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  children: [
                    // Drag handle
                    const SizedBox(height: 12),
                    Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: AppThemeColors.divider(ctx),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.cyan.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.people_rounded, color: AppColors.cyan, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('select_friends_title'),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppThemeColors.primaryText(ctx),
                                ),
                              ),
                              Text(
                                allFriends.length == 1
                                    ? t('one_friend_label')
                                    : '${allFriends.length} ${t('friends_count_label')}',
                                style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx)),
                              ),
                            ],
                          ),
                          const Spacer(),
                          if (tempSelected.isNotEmpty)
                            TextButton(
                              onPressed: () => setSheetState(() => tempSelected.clear()),
                              child: Text(t('deselect_all_label'),
                                  style: const TextStyle(color: AppColors.cyan, fontSize: 13)),
                            ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: Icon(Icons.close, color: AppThemeColors.secondaryText(ctx), size: 22),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Select-all row
                    if (allFriends.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Checkbox(
                              value: allSelected,
                              activeColor: AppColors.cyan,
                              onChanged: (val) {
                                setSheetState(() {
                                  if (val == true) {
                                    tempSelected.addAll(allFriends
                                        .where((f) => !_isBlocked((f['email'] ?? '').toString()))
                                        .map((f) => (f['email'] ?? '').toString()));
                                  } else {
                                    tempSelected.clear();
                                  }
                                });
                              },
                            ),
                            Text(t('select_all_label'),
                                style: TextStyle(color: AppThemeColors.primaryText(ctx), fontSize: 14)),
                            const Spacer(),
                            if (tempSelected.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.cyan.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${tempSelected.length} ${t('selected_label')}',
                                  style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                      ),

                    // Search box
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppThemeColors.surfaceBg(ctx),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: TextField(
                          autofocus: false,
                          style: TextStyle(color: AppThemeColors.primaryText(ctx)),
                          onChanged: (v) => setSheetState(() => searchQuery = v),
                          decoration: InputDecoration(
                            hintText: t('search_by_name_or_email_placeholder'),
                            hintStyle: TextStyle(color: AppThemeColors.mutedText(ctx), fontSize: 14),
                            prefixIcon: Icon(Icons.search, color: AppThemeColors.mutedText(ctx), size: 20),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Divider(height: 1, color: AppThemeColors.divider(ctx)),

                    // Friend list
                    Expanded(
                      child: allFriends.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.people_outline, size: 48, color: AppThemeColors.mutedText(ctx)),
                                  const SizedBox(height: 12),
                                  Text(t('no_friends_found_label'),
                                      style: TextStyle(color: AppThemeColors.mutedText(ctx), fontSize: 14)),
                                ],
                              ),
                            )
                          : filtered.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.search_off, size: 48, color: AppThemeColors.mutedText(ctx)),
                                      const SizedBox(height: 12),
                                      Text(
                                        '${t('no_match_for_label')} "$searchQuery"',
                                        style: TextStyle(color: AppThemeColors.mutedText(ctx), fontSize: 14),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  controller: scrollController,
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (_, idx) {
                                    final f = filtered[idx];
                                    final email = (f['email'] ?? '').toString();
                                    final name = (f['name'] ?? f['username'] ?? '').toString();
                                    final isBlocked = _isBlocked(email);
                                    final isSelected = tempSelected.contains(email);
                                    final displayName = name.isNotEmpty ? name : email;
                                    final initials = ah.initials(name, email);
                                    final color = ah.avatarColor(displayName);

                                    return GestureDetector(
                                      onTap: () {
                                        if (isBlocked) return;
                                        setSheetState(() {
                                          if (isSelected) {
                                            tempSelected.remove(email);
                                          } else {
                                            tempSelected.add(email);
                                          }
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: isBlocked
                                              ? Colors.red.withValues(alpha: 0.04)
                                              : isSelected
                                                  ? AppColors.cyan.withValues(alpha: 0.08)
                                                  : AppThemeColors.surfaceBg(ctx),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: isBlocked
                                                ? Colors.red.withValues(alpha: 0.2)
                                                : isSelected
                                                    ? AppColors.cyan.withValues(alpha: 0.5)
                                                    : AppThemeColors.border(ctx),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            // Avatar
                                            Container(
                                              width: 46, height: 46,
                                              decoration: BoxDecoration(
                                                color: isBlocked
                                                    ? Colors.red[100]
                                                    : color.withValues(alpha: 0.18),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  initials,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: isBlocked ? Colors.red : color,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 14),

                                            // Name & email
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name.isNotEmpty ? name : email,
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w600,
                                                      color: isBlocked
                                                          ? Colors.red[700]
                                                          : AppThemeColors.primaryText(ctx),
                                                    ),
                                                  ),
                                                  if (name.isNotEmpty)
                                                    Text(
                                                      email,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: isBlocked
                                                            ? Colors.red[400]
                                                            : AppThemeColors.secondaryText(ctx),
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                ],
                                              ),
                                            ),

                                            // Trailing: blocked label or checkbox
                                            if (isBlocked)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(t('blocked_label'),
                                                    style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w600)),
                                              )
                                            else
                                              Checkbox(
                                                value: isSelected,
                                                activeColor: AppColors.cyan,
                                                onChanged: (_) {
                                                  setSheetState(() {
                                                    if (isSelected) {
                                                      tempSelected.remove(email);
                                                    } else {
                                                      tempSelected.add(email);
                                                    }
                                                  });
                                                },
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),

                    // Done button pinned at bottom
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 4,
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          tempSelected.isEmpty
                              ? t('done')
                              : '${t('done')} (${tempSelected.length})',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (mounted) {
      final newMemberUsers = Map<String, Map<String, dynamic>>.from(_memberUsers);
      for (final f in allFriends) {
        final e = (f['email'] ?? '').toString();
        if (tempSelected.contains(e)) {
          newMemberUsers[e] = {
            '_id': (f['_id'] ?? '').toString(),
            'name': (f['name'] ?? f['username'] ?? '').toString(),
          };
        }
      }
      setState(() {
        _memberEmails = tempSelected.toList();
        _memberUsers = newMemberUsers;
      });
    }
  }

  Future<void> _loadUserGroups() async {
    if (_userGroups.isNotEmpty || _loadingGroups) return;
    setState(() => _loadingGroups = true);
    try {
      final res = await ApiClient.get('/api/group-transactions/user-groups');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        // API already filters to groups where user is creator or member — no extra filter needed
        final allGroups = List<Map<String, dynamic>>.from(data['groups'] ?? []);
        if (mounted) setState(() { _userGroups = allGroups; _loadingGroups = false; });
      } else {
        if (mounted) setState(() => _loadingGroups = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingGroups = false);
    }
  }

  Color _parseGroupColor(dynamic colorStr) {
    if (colorStr == null) return AppColors.blue;
    try {
      final hex = colorStr.toString().replaceFirst('#', '');
      if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
      if (hex.length == 8) return Color(int.parse(hex, radix: 16));
    } catch (_) {}
    return AppColors.blue;
  }

  Widget _buildModeTab(BuildContext ctx, int current, int value, IconData icon, String label, VoidCallback onTap) {
    final isActive = current == value;
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          gradient: isActive ? const LinearGradient(colors: [AppColors.cyan, AppColors.blue]) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: isActive ? Colors.white : AppThemeColors.secondaryText(ctx)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : AppThemeColors.secondaryText(ctx))),
        ]),
      ),
    ));
  }

  Future<void> _addMembersFromCommunities() async {
    if (_userCommunities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No communities found. Join or create a community first.')),
      );
      return;
    }

    final myEmail = Provider.of<SessionProvider>(context, listen: false)
        .user?['email']?.toString().toLowerCase() ?? '';

    final tempSelected = Set<String>.from(_memberEmails);
    final tempMemberUsers = Map<String, Map<String, dynamic>>.from(_memberUsers);
    final originalEmails = Set<String>.from(_memberEmails);
    final originalCount = _memberEmails.length;
    int modeTab = 0;
    String? statusMsg;

    String getCMemberEmail(Map m) {
      final u = m['user'];
      if (u is Map) return (u['email'] ?? '').toString().toLowerCase().trim();
      return '';
    }
    String getCMemberName(Map m) {
      final u = m['user'];
      if (u is Map) return (u['name'] ?? u['username'] ?? '').toString();
      return '';
    }
    String getCMemberId(Map m) {
      final u = m['user'];
      if (u is Map) return (u['_id'] ?? '').toString();
      return '';
    }
    List<Map> getCMembers(Map c) {
      final raw = c['members'];
      if (raw is! List) return [];
      return raw.whereType<Map>().where((m) {
        final e = getCMemberEmail(m);
        return e.isNotEmpty;
      }).toList();
    }
    Color parseCColor(dynamic v) {
      try {
        if (v is String && v.startsWith('#')) return Color(int.parse('FF${v.replaceFirst('#', '')}', radix: 16));
      } catch (_) {}
      return AppColors.cyan;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final List<Map<String, dynamic>> allPickMembers = [];
          if (modeTab == 1) {
            final seen = <String>{};
            for (final c in _userCommunities) {
              for (final m in getCMembers(c)) {
                final me = getCMemberEmail(m);
                if (me.isNotEmpty && seen.add(me)) {
                  allPickMembers.add(Map<String, dynamic>.from(m));
                }
              }
            }
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.82,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollCtrl) => Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(ctx),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(children: [
                const SizedBox(height: 12),
                Center(child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)),
                )),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.hub_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Add from Communities', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
                      Text('${_userCommunities.length} communit${_userCommunities.length == 1 ? 'y' : 'ies'}', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
                    ])),
                    if (tempSelected.length > originalCount)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                        child: Text('+${tempSelected.length - originalCount} added', style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    const SizedBox(width: 8),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: AppThemeColors.secondaryText(ctx))),
                  ]),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: AppThemeColors.surfaceBg(ctx), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      _buildModeTab(ctx, modeTab, 0, Icons.hub_rounded, 'Choose Community', () => setSheet(() { modeTab = 0; statusMsg = null; })),
                      _buildModeTab(ctx, modeTab, 1, Icons.person_search_rounded, 'Pick Members', () => setSheet(() { modeTab = 1; statusMsg = null; })),
                    ]),
                  ),
                ),
                if (statusMsg != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.withValues(alpha: 0.3))),
                      child: Row(children: [
                        const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                        const SizedBox(width: 8),
                        Flexible(child: Text(statusMsg!, style: const TextStyle(color: Colors.green, fontSize: 13))),
                      ]),
                    ),
                  ),
                const SizedBox(height: 8),
                Divider(height: 1, color: AppThemeColors.divider(ctx)),
                Expanded(
                  child: modeTab == 0
                    ? ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: _userCommunities.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, ci) {
                          final c = _userCommunities[ci];
                          final cName = (c['name'] ?? 'Community').toString();
                          final cMembers = getCMembers(c);
                          final cColor = parseCColor(c['color']);
                          final selectableC = cMembers.where((m) {
                            final e = getCMemberEmail(m);
                            return e != myEmail && !originalEmails.contains(e);
                          }).toList();
                          final allAdded = selectableC.isNotEmpty && selectableC.every((m) => tempSelected.contains(getCMemberEmail(m)));

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppThemeColors.surfaceBg(ctx),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: AppThemeColors.border(ctx)),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Container(
                                  width: 44, height: 44,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [cColor.withValues(alpha: 0.8), cColor], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Center(child: Text(cName.isNotEmpty ? cName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(cName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
                                  Text('${cMembers.length} member${cMembers.length == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
                                ])),
                                TextButton.icon(
                                  onPressed: selectableC.isEmpty ? null : () {
                                    setSheet(() {
                                      if (allAdded) {
                                        for (final m in selectableC) {
                                          final me = getCMemberEmail(m);
                                          tempSelected.remove(me);
                                          tempMemberUsers.remove(me);
                                        }
                                        statusMsg = 'Removed new additions from $cName';
                                      } else {
                                        int added = 0;
                                        for (final m in selectableC) {
                                          final me = getCMemberEmail(m);
                                          if (me.isNotEmpty && tempSelected.add(me)) {
                                            tempMemberUsers[me] = { '_id': getCMemberId(m), 'name': getCMemberName(m) };
                                            added++;
                                          }
                                        }
                                        statusMsg = 'Added $added member${added == 1 ? '' : 's'} from $cName';
                                      }
                                    });
                                  },
                                  icon: Icon(allAdded ? Icons.remove_circle_outline : Icons.group_add, size: 16, color: selectableC.isEmpty ? AppThemeColors.mutedText(ctx) : (allAdded ? Colors.orange : AppColors.cyan)),
                                  label: Text(allAdded ? 'Remove All' : (selectableC.isEmpty ? 'All joined' : 'Add All'), style: TextStyle(fontSize: 12, color: selectableC.isEmpty ? AppThemeColors.mutedText(ctx) : (allAdded ? Colors.orange : AppColors.cyan))),
                                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                ),
                              ]),
                              if (cMembers.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: cMembers.map((m) {
                                    final me = getCMemberEmail(m);
                                    final mn = getCMemberName(m);
                                    final mId = getCMemberId(m);
                                    final alreadyIn = originalEmails.contains(me) || me == myEmail;
                                    final isSelected = tempSelected.contains(me);
                                    final initials = mn.isNotEmpty ? mn[0].toUpperCase() : (me.isNotEmpty ? me[0].toUpperCase() : '?');
                                    final avatarWidget = SizedBox(
                                      width: 18, height: 18,
                                      child: ClipOval(child: Stack(fit: StackFit.expand, children: [
                                        Container(
                                          color: alreadyIn ? AppThemeColors.border(ctx) : AppColors.cyan.withValues(alpha: 0.15),
                                          child: Center(child: Text(initials, style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: alreadyIn ? AppThemeColors.mutedText(ctx) : AppColors.cyan))),
                                        ),
                                        if (mId.isNotEmpty)
                                          Image.network('${ApiConfig.baseUrl}/api/users/$mId/profile-image', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                                      ])),
                                    );
                                    if (alreadyIn) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: AppThemeColors.surfaceBg(ctx),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: AppThemeColors.border(ctx)),
                                        ),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          avatarWidget,
                                          const SizedBox(width: 5),
                                          Text(
                                            mn.isNotEmpty ? mn.split(' ')[0] : me.split('@')[0],
                                            style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(ctx)),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(Icons.check_circle, size: 12, color: Colors.green.withValues(alpha: 0.7)),
                                        ]),
                                      );
                                    }
                                    return GestureDetector(
                                      onTap: () => setSheet(() {
                                        if (isSelected) {
                                          tempSelected.remove(me);
                                          tempMemberUsers.remove(me);
                                        } else {
                                          tempSelected.add(me);
                                          tempMemberUsers[me] = { '_id': mId, 'name': mn };
                                        }
                                      }),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: isSelected ? AppColors.cyan.withValues(alpha: 0.15) : AppThemeColors.cardBg(ctx),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: isSelected ? AppColors.cyan : AppThemeColors.border(ctx)),
                                        ),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          avatarWidget,
                                          const SizedBox(width: 5),
                                          if (isSelected) ...[
                                            const Icon(Icons.check, size: 12, color: AppColors.cyan),
                                            const SizedBox(width: 3),
                                          ],
                                          Text(
                                            mn.isNotEmpty ? mn.split(' ')[0] : me.split('@')[0],
                                            style: TextStyle(fontSize: 12, color: isSelected ? AppColors.cyan : AppThemeColors.primaryText(ctx), fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal),
                                          ),
                                        ]),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ]),
                          );
                        },
                      )
                    : ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: allPickMembers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final m = allPickMembers[i];
                          final me = getCMemberEmail(m);
                          final mn = getCMemberName(m);
                          final mId = getCMemberId(m);
                          final alreadyIn = originalEmails.contains(me) || me == myEmail;
                          final isSelected = tempSelected.contains(me);
                          final initials = mn.isNotEmpty ? mn[0].toUpperCase() : (me.isNotEmpty ? me[0].toUpperCase() : '?');
                          return GestureDetector(
                            onTap: alreadyIn ? null : () => setSheet(() {
                              if (isSelected) {
                                tempSelected.remove(me);
                                tempMemberUsers.remove(me);
                              } else {
                                tempSelected.add(me);
                                tempMemberUsers[me] = { '_id': mId, 'name': mn };
                              }
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: alreadyIn
                                  ? AppThemeColors.surfaceBg(ctx)
                                  : (isSelected ? AppColors.cyan.withValues(alpha: 0.08) : AppThemeColors.surfaceBg(ctx)),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: alreadyIn
                                  ? AppThemeColors.border(ctx)
                                  : (isSelected ? AppColors.cyan.withValues(alpha: 0.5) : AppThemeColors.border(ctx))),
                              ),
                              child: Row(children: [
                                SizedBox(
                                  width: 44, height: 44,
                                  child: ClipOval(child: Stack(fit: StackFit.expand, children: [
                                    Container(
                                      color: alreadyIn ? AppThemeColors.border(ctx) : AppColors.cyan.withValues(alpha: 0.15),
                                      child: Center(child: Text(initials, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: alreadyIn ? AppThemeColors.mutedText(ctx) : AppColors.cyan))),
                                    ),
                                    if (mId.isNotEmpty)
                                      Image.network('${ApiConfig.baseUrl}/api/users/$mId/profile-image', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                                  ])),
                                ),
                                const SizedBox(width: 14),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(mn.isNotEmpty ? mn : me, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: alreadyIn ? AppThemeColors.mutedText(ctx) : AppThemeColors.primaryText(ctx))),
                                  if (alreadyIn)
                                    const Text('Already in group', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w500))
                                  else if (mn.isNotEmpty)
                                    Text(me, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx)), overflow: TextOverflow.ellipsis),
                                ])),
                                alreadyIn
                                  ? const Icon(Icons.how_to_reg_rounded, color: Colors.green, size: 20)
                                  : Checkbox(
                                      value: isSelected,
                                      activeColor: AppColors.cyan,
                                      onChanged: (_) => setSheet(() {
                                        if (isSelected) {
                                          tempSelected.remove(me);
                                          tempMemberUsers.remove(me);
                                        } else {
                                          tempSelected.add(me);
                                          tempMemberUsers[me] = { '_id': mId, 'name': mn };
                                        }
                                      }),
                                    ),
                              ]),
                            ),
                          );
                        },
                      ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      tempSelected.length == originalCount ? 'Done' : 'Done (+${tempSelected.length - originalCount})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );

    if (mounted) {
      final newMemberUsers = Map<String, Map<String, dynamic>>.from(_memberUsers);
      newMemberUsers.addAll(tempMemberUsers);
      setState(() {
        _memberEmails = tempSelected.toList();
        _memberUsers = newMemberUsers;
      });
    }
  }

  Future<void> _addMembersFromGroups() async {
    await _loadUserGroups();
    if (!mounted) return;
    if (_userGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No groups found. Create a group first.')),
      );
      return;
    }

    final myEmail = Provider.of<SessionProvider>(context, listen: false)
        .user?['email']?.toString().toLowerCase() ?? '';

    final tempSelected = Set<String>.from(_memberEmails);
    final tempMemberUsers = Map<String, Map<String, dynamic>>.from(_memberUsers);
    final originalEmails = Set<String>.from(_memberEmails);
    int modeTab = 0;
    String? groupStatusMsg;

    String getMemberEmail(Map m) {
      final direct = m['email'];
      if (direct != null && direct.toString().isNotEmpty) return direct.toString().toLowerCase().trim();
      final user = m['user'];
      if (user is Map) return (user['email'] ?? '').toString().toLowerCase().trim();
      return '';
    }
    String getMemberName(Map m) {
      final direct = m['name'] ?? m['username'];
      if (direct != null && direct.toString().isNotEmpty) return direct.toString();
      final user = m['user'];
      if (user is Map) return (user['name'] ?? user['username'] ?? '').toString();
      return '';
    }
    String getMemberId(Map m) {
      final direct = m['_id'] ?? m['userId'];
      if (direct != null && direct.toString().isNotEmpty) return direct.toString();
      final user = m['user'];
      if (user is Map) return (user['_id'] ?? '').toString();
      return '';
    }
    List<Map> getGroupMembers(Map g) {
      final raw = g['members'];
      if (raw is! List) return [];
      final members = raw.whereType<Map>().toList();
      return members.where((m) {
        if ((m['leftAt'] != null)) return false;
        final me = getMemberEmail(m);
        return me.isNotEmpty;
      }).toList();
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // Pre-compute member list for Pick Members tab outside the widget tree to avoid IIFE-during-build issues
          final List<Map<String, dynamic>> allPickMembers = [];
          final Map<String, String> pickMemberGroupName = {};
          if (modeTab == 1) {
            final seen = <String>{};
            for (final g in _userGroups) {
              final gName = (g['title'] ?? 'Group').toString();
              for (final m in getGroupMembers(g)) {
                final me = getMemberEmail(m);
                if (me.isNotEmpty && seen.add(me)) {
                  allPickMembers.add(Map<String, dynamic>.from(m));
                  pickMemberGroupName[me] = gName;
                }
              }
            }
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.82,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollCtrl) => Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(ctx),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(children: [
                const SizedBox(height: 12),
                Center(child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)),
                )),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.group_work_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Add from Your Groups', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
                      Text('${_userGroups.length} group${_userGroups.length == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
                    ])),
                    if (tempSelected.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                        child: Text('${tempSelected.length} added', style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    const SizedBox(width: 8),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: AppThemeColors.secondaryText(ctx))),
                  ]),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: AppThemeColors.surfaceBg(ctx), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      _buildModeTab(ctx, modeTab, 0, Icons.group_rounded, 'Choose Group', () => setSheet(() { modeTab = 0; groupStatusMsg = null; })),
                      _buildModeTab(ctx, modeTab, 1, Icons.person_search_rounded, 'Pick Members', () => setSheet(() { modeTab = 1; groupStatusMsg = null; })),
                    ]),
                  ),
                ),
                if (groupStatusMsg != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.withValues(alpha: 0.3))),
                      child: Row(children: [
                        const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                        const SizedBox(width: 8),
                        Flexible(child: Text(groupStatusMsg!, style: const TextStyle(color: Colors.green, fontSize: 13))),
                      ]),
                    ),
                  ),
                const SizedBox(height: 8),
                Divider(height: 1, color: AppThemeColors.divider(ctx)),
                Expanded(
                  child: modeTab == 0
                    ? ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: _userGroups.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, gi) {
                          final g = _userGroups[gi];
                          final gId = (g['_id'] ?? '').toString();
                          final gName = (g['title'] ?? 'Group').toString();
                          final gColor = _parseGroupColor(g['color']);
                          final members = getGroupMembers(g);
                          final gImgUrl = gId.isNotEmpty ? '${ApiConfig.baseUrl}/api/group-transactions/$gId/image' : null;

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppThemeColors.surfaceBg(ctx),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: AppThemeColors.border(ctx)),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Container(
                                  width: 48, height: 48,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [gColor.withValues(alpha: 0.8), gColor], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: gImgUrl != null
                                      ? Image.network(gImgUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Text(gName.isNotEmpty ? gName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20))))
                                      : Center(child: Text(gName.isNotEmpty ? gName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20))),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(gName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
                                  Text('${members.length} member${members.length == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
                                ])),
                                SizedBox(
                                  width: 44,
                                  height: 24,
                                  child: members.isEmpty ? const SizedBox() : Stack(
                                    children: List.generate(
                                      members.length > 4 ? 4 : members.length, (si) {
                                        final m = members[si];
                                        final mId = getMemberId(m);
                                        final mName = getMemberName(m);
                                        final initials = mName.isNotEmpty ? mName[0].toUpperCase() : '?';
                                        return Positioned(
                                          left: si * 14.0,
                                          child: Container(
                                            width: 24, height: 24,
                                            decoration: BoxDecoration(
                                              color: AppColors.cyan.withValues(alpha: 0.15),
                                              shape: BoxShape.circle,
                                              border: Border.all(color: AppThemeColors.cardBg(ctx), width: 1.5),
                                            ),
                                            child: ClipOval(child: Stack(fit: StackFit.expand, children: [
                                              Center(child: Text(initials, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.cyan))),
                                              if (mId.isNotEmpty)
                                                Image.network('${ApiConfig.baseUrl}/api/users/$mId/profile-image', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                                            ])),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 10),
                              Builder(builder: (ctx2) {
                                final selectableG = members.where((m) {
                                  final me = getMemberEmail(m);
                                  return me.isNotEmpty && me != myEmail && !originalEmails.contains(me);
                                }).toList();
                                final allAdded = selectableG.isNotEmpty && selectableG.every((m) => tempSelected.contains(getMemberEmail(m)));
                                return SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: allAdded
                                          ? Colors.red.withValues(alpha: 0.10)
                                          : AppColors.cyan.withValues(alpha: 0.12),
                                      foregroundColor: allAdded ? Colors.red : AppColors.cyan,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                    icon: Icon(allAdded ? Icons.remove_circle_outline_rounded : Icons.group_add_rounded, size: 16),
                                    label: Text(allAdded ? 'Remove All' : (selectableG.isEmpty ? 'All joined' : 'Add All Members'), style: const TextStyle(fontWeight: FontWeight.w600)),
                                    onPressed: selectableG.isEmpty ? null : () {
                                      if (allAdded) {
                                        int removed = 0;
                                        for (final m in selectableG) {
                                          final me = getMemberEmail(m);
                                          if (tempSelected.remove(me)) { tempMemberUsers.remove(me); removed++; }
                                        }
                                        setSheet(() => groupStatusMsg = '$removed member${removed == 1 ? '' : 's'} removed');
                                      } else {
                                        int added = 0, skipped = 0;
                                        for (final m in selectableG) {
                                          final me = getMemberEmail(m);
                                          if (tempSelected.contains(me)) { skipped++; continue; }
                                          tempSelected.add(me);
                                          tempMemberUsers[me] = {'_id': getMemberId(m), 'name': getMemberName(m)};
                                          added++;
                                        }
                                        String msg = '$added added';
                                        if (skipped > 0) msg += ', $skipped already selected';
                                        setSheet(() => groupStatusMsg = msg);
                                      }
                                    },
                                  ),
                                );
                              }),
                            ]),
                          );
                        },
                      )
                    : Column(children: [
                        if (allPickMembers.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${allPickMembers.length} member${allPickMembers.length == 1 ? '' : 's'} across all groups',
                                  style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx)),
                                ),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.cyan,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: Icon(
                                    allPickMembers.where((m) { final _e = getMemberEmail(m); return _e != myEmail && !originalEmails.contains(_e); }).every((m) => tempSelected.contains(getMemberEmail(m)))
                                        ? Icons.deselect_rounded
                                        : Icons.select_all_rounded,
                                    size: 15,
                                  ),
                                  label: Text(
                                    allPickMembers.where((m) { final _e = getMemberEmail(m); return _e != myEmail && !originalEmails.contains(_e); }).every((m) => tempSelected.contains(getMemberEmail(m)))
                                        ? 'Deselect All'
                                        : 'Select All',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  onPressed: () {
                                    final selectables = allPickMembers.where((m) { final _e = getMemberEmail(m); return _e != myEmail && !originalEmails.contains(_e); }).toList();
                                    final allSelected = selectables.every((m) => tempSelected.contains(getMemberEmail(m)));
                                    if (allSelected) {
                                      setSheet(() {
                                        for (final m in selectables) {
                                          final me = getMemberEmail(m);
                                          tempSelected.remove(me);
                                          tempMemberUsers.remove(me);
                                        }
                                      });
                                    } else {
                                      setSheet(() {
                                        for (final m in selectables) {
                                          final me = getMemberEmail(m);
                                          if (me.isNotEmpty && !tempSelected.contains(me)) {
                                            tempSelected.add(me);
                                            tempMemberUsers[me] = {'_id': getMemberId(m), 'name': getMemberName(m)};
                                          }
                                        }
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        Expanded(child: ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: allPickMembers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, mi) {
                            final m = allPickMembers[mi];
                            final me = getMemberEmail(m);
                            final mName = getMemberName(m);
                            final mId = getMemberId(m);
                            final fromGroup = pickMemberGroupName[me] ?? '';
                            final initials = mName.isNotEmpty ? mName[0].toUpperCase() : (me.isNotEmpty ? me[0].toUpperCase() : '?');
                            final alreadyIn = originalEmails.contains(me) || me == myEmail;
                            final isSelected = tempSelected.contains(me);

                            return GestureDetector(
                              onTap: alreadyIn ? null : () {
                                if (isSelected) {
                                  setSheet(() { tempSelected.remove(me); tempMemberUsers.remove(me); });
                                } else {
                                  tempMemberUsers[me] = {'_id': mId, 'name': mName};
                                  setSheet(() => tempSelected.add(me));
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: alreadyIn
                                    ? AppThemeColors.surfaceBg(ctx)
                                    : (isSelected ? AppColors.cyan.withValues(alpha: 0.08) : AppThemeColors.surfaceBg(ctx)),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: alreadyIn
                                    ? AppThemeColors.border(ctx)
                                    : (isSelected ? AppColors.cyan.withValues(alpha: 0.5) : AppThemeColors.border(ctx))),
                                ),
                                child: Row(children: [
                                  SizedBox(
                                    width: 44, height: 44,
                                    child: ClipOval(child: Stack(fit: StackFit.expand, children: [
                                      Container(
                                        color: alreadyIn ? AppThemeColors.border(ctx) : AppColors.cyan.withValues(alpha: 0.15),
                                        child: Center(child: Text(initials, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: alreadyIn ? AppThemeColors.mutedText(ctx) : AppColors.cyan))),
                                      ),
                                      if (mId.isNotEmpty)
                                        Image.network('${ApiConfig.baseUrl}/api/users/$mId/profile-image', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                                    ])),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(mName.isNotEmpty ? mName : me, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: alreadyIn ? AppThemeColors.mutedText(ctx) : AppThemeColors.primaryText(ctx))),
                                    if (alreadyIn)
                                      const Text('Already in group', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w500))
                                    else ...[
                                      Text(mName.isNotEmpty ? me : '', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx)), overflow: TextOverflow.ellipsis),
                                      if (fromGroup.isNotEmpty)
                                        Text('from: $fromGroup', style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(ctx))),
                                    ],
                                  ])),
                                  alreadyIn
                                    ? const Icon(Icons.how_to_reg_rounded, color: Colors.green, size: 20)
                                    : Checkbox(
                                        value: isSelected,
                                        activeColor: AppColors.cyan,
                                        onChanged: (_) {
                                          if (isSelected) {
                                            setSheet(() { tempSelected.remove(me); tempMemberUsers.remove(me); });
                                          } else {
                                            tempMemberUsers[me] = {'_id': mId, 'name': mName};
                                            setSheet(() => tempSelected.add(me));
                                          }
                                        },
                                      ),
                                ]),
                              ),
                            );
                          },
                        )),
                      ]),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        tempSelected.isEmpty ? 'Done' : 'Done (${tempSelected.length})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );

    if (mounted) {
      setState(() {
        _memberEmails = tempSelected.toList();
        _memberUsers = tempMemberUsers;
      });
    }
  }

  Future<void> _pickGroupImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked != null && mounted) setState(() => _selectedImage = picked);
  }

  Future<void> _uploadGroupImageAfterCreate(String groupId) async {
    if (_selectedImage == null) return;
    try {
      final bytes = await _selectedImage!.readAsBytes();
      await ApiClient.putMultipart(
        '/api/group-transactions/$groupId/image',
        files: [ApiMultipartFile(field: 'groupImage', filename: _selectedImage!.name, bytes: bytes)],
      );
    } catch (_) {}
  }

  Future<void> _pickColor() async {
    final t = AppLocalizations.of(context).t;
    Color picked = _selectedColor ?? Colors.blue;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(context),
        title: Text(t('pick_group_color'),
            style: TextStyle(color: AppThemeColors.primaryText(context))),
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
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('cancel')),
          ),
          TextButton(
            onPressed: () {
              setState(() => _selectedColor = picked);
              Navigator.of(context).pop();
            },
            child: Text(t('select')),
          ),
        ],
      ),
    );
  }

  String? _colorHex() {
    if (_selectedColor == null) return null;
    return '#${_selectedColor!.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }

  Future<void> _offerShareGroupInvite(Map<String, dynamic> group) async {
    final groupName = (group['title'] ?? 'the group').toString();
    final groupColor = _parseGroupColor(group['color']);
    final appLink = await fetchAppInviteLink();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 22),
            // Group icon with animated gradient
            Container(
              width: 78, height: 78,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [groupColor, AppColors.blue],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(color: groupColor.withValues(alpha: 0.40), blurRadius: 18, offset: const Offset(0, 7))],
              ),
              child: const Icon(Icons.group_rounded, color: Colors.white, size: 38),
            ),
            const SizedBox(height: 16),
            Text('Group Created!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
            const SizedBox(height: 6),
            Text(
              '"$groupName" is ready. Share the invite so friends can join!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(ctx), height: 1.4),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('via referral invite link', style: TextStyle(fontSize: 12, color: AppColors.cyan, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 26),
            // Share Invite button (gradient)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.30), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.share_rounded, color: Colors.white, size: 18),
                label: const Text('Share Invite Link', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                onPressed: () async {
                  Navigator.pop(ctx);
                  String msg = '👥 Join "$groupName" on LenDen!\n📱 Download the app and ask the group admin for the join code.';
                  if (appLink.isNotEmpty) msg += '\n------------------\n$appLink';
                  await Share.share(msg, subject: 'Join $groupName on LenDen');
                  ApiClient.post('/api/referral/share', body: {'channel': 'group_invite'}).ignore();
                },
              ),
            ),
            const SizedBox(height: 10),
            // Share as Note
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  side: const BorderSide(color: AppColors.tricolorGreen),
                  foregroundColor: AppColors.tricolorGreen,
                ),
                icon: const Icon(Icons.note_add_rounded, size: 18),
                label: const Text('Share as Note', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                onPressed: () {
                  Navigator.pop(ctx);
                  final content = StringBuffer();
                  content.writeln('Group: $groupName');
                  content.writeln('Download LenDen and ask the group admin for the join code.');
                  if (appLink.isNotEmpty) content.writeln('App: $appLink');
                  showShareAsNoteSheet(context, title: 'Join $groupName on LenDen', content: content.toString().trim());
                },
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Skip for now', style: TextStyle(color: AppThemeColors.mutedText(ctx), fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createGroupWithCoins() async {
    final t = AppLocalizations.of(context).t;
    if (_hasBlockedMembers()) {
      showBlockedUserDialog(context);
      return;
    }
    setState(() {
      _creatingGroup = true;
      _error = null;
    });
    try {
      final res = await ApiClient.post('/api/group-transactions/with-coins', body: {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'memberEmails': _memberEmails,
        'color': _colorHex(),
      });
      final data = json.decode(res.body);
      if (res.statusCode == 201) {
        final session = Provider.of<SessionProvider>(context, listen: false);
        session.loadFreebieCounts();
        if (mounted) {
          final giftCardAwarded = data['giftCardAwarded'] as bool?;
          final awardedCard = data['awardedCard'];
          if (giftCardAwarded == true && awardedCard != null) {
            ElegantNotification.success(
              title: Text(t('congratulations_title')),
              description: Text(t('you_won_a_gift_card')),
              action: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GiftCardPage())),
                child: Text(t('view_label'), style: const TextStyle(color: Colors.blue)),
              ),
            ).show(context);
          } else {
            ElegantNotification.success(
              title: Text(t('success')),
              description: Text(t('group_created_success_msg')),
            ).show(context);
          }
          final groupId = data['group']?['_id']?.toString() ?? '';
          if (groupId.isNotEmpty) await _uploadGroupImageAfterCreate(groupId);
          await _offerShareGroupInvite(Map<String, dynamic>.from(data['group'] ?? {}));
          if (mounted) Navigator.pop(context, data['group']);
        }
      } else if (res.statusCode == 403) {
        final msg = (data['error'] ?? t('forbidden_label')).toString();
        if (msg.toLowerCase().contains('blocked')) {
          showBlockedUserDialog(context, message: msg);
        } else {
          showInsufficientCoinsDialog(context);
        }
      } else if (res.statusCode == 429) {
        showDailyLimitDialog(context, message: (data['error'] ?? t('daily_limit_reached')).toString());
      } else {
        setState(() => _error = data['error'] ?? t('failed_to_create_group_msg'));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _creatingGroup = false);
    }
  }

  Future<void> _createGroup() async {
    final t = AppLocalizations.of(context).t;
    final session = Provider.of<SessionProvider>(context, listen: false);

    if (_hasBlockedMembers()) {
      showBlockedUserDialog(context);
      return;
    }

    if (!session.hasFeature('group_creation')) {
      await Future.wait([
        session.loadFreebieCounts(),
        _loadDailyLimits(),
      ]);
    }

    // Daily limit expired → hard block; free attempts are also paused until tomorrow.
    if (!session.hasFeature('group_creation') &&
        _dailyGroupRemaining != null &&
        _dailyGroupRemaining! <= 0) {
      showDailyLimitDialog(context, message: t('daily_group_limit_reached_msg'));
      return;
    }

    // useCoins confirmed before navigation — skip the dialog.
    if (!session.hasFeature('group_creation') && widget.useCoins) {
      _createGroupWithCoins();
      return;
    }

    // Daily limit OK but free attempts exhausted → offer coins.
    final shouldUseCoins = !session.hasFeature('group_creation') &&
        (session.freeGroupsRemaining ?? 0) <= 0;

    if (shouldUseCoins) {
      final int coinCost = session.groupCreationCoinCost;
      final coins = session.lenDenCoins ?? 0;
      if (coins < coinCost) {
        coins == 0 ? showZeroCoinsDialog(context) : showInsufficientCoinsDialog(context);
        return;
      }
      final useCoins = await showFreeAttemptsExhaustedDialog(
        context,
        featureName: t('group_creation_feature_label'),
        coinCost: coinCost,
        currentCoins: coins,
      );
      if (useCoins == true) _createGroupWithCoins();
      return;
    }

    setState(() {
      _creatingGroup = true;
      _error = null;
    });
    try {
      final res = await ApiClient.post('/api/group-transactions', body: {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'memberEmails': _memberEmails,
        'color': _colorHex(),
        if (_selectedCommunityIds.isNotEmpty) 'communityIds': _selectedCommunityIds,
      });
      final data = json.decode(res.body);
      if (res.statusCode == 201) {
        session.loadFreebieCounts();
        if (mounted) {
          final giftCardAwarded = data['giftCardAwarded'] as bool?;
          final awardedCard = data['awardedCard'];
          if (giftCardAwarded == true && awardedCard != null) {
            ElegantNotification.success(
              title: Text(t('congratulations_title')),
              description: Text(t('you_won_a_gift_card')),
              action: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GiftCardPage())),
                child: Text(t('view_label'), style: const TextStyle(color: Colors.blue)),
              ),
            ).show(context);
          } else {
            ElegantNotification.success(
              title: Text(t('success')),
              description: Text(t('group_created_success_msg')),
            ).show(context);
          }
          final groupId = data['group']?['_id']?.toString() ?? '';
          if (groupId.isNotEmpty) await _uploadGroupImageAfterCreate(groupId);
          await _offerShareGroupInvite(Map<String, dynamic>.from(data['group'] ?? {}));
          if (mounted) Navigator.pop(context, data['group']);
        }
      } else {
        final msg = (data['error'] ?? t('failed_to_create_group_msg')).toString();
        if (msg.toLowerCase().contains('blocked')) {
          showBlockedUserDialog(context, message: msg);
          return;
        }
        if (msg.toLowerCase().contains('daily limit')) {
          showDailyLimitDialog(context, message: msg);
          return;
        }
        // Server says free groups exhausted — stale client cache.
        // Refresh counts and offer the coins flow.
        if (msg.toLowerCase().contains('run out') ||
            msg.toLowerCase().contains('no free') ||
            msg.toLowerCase().contains('out of free') ||
            msg.toLowerCase().contains('free group')) {
          session.loadFreebieCounts();
          _loadDailyLimits();
          if (mounted) {
            setState(() => _creatingGroup = false);
            // Re-enter create flow; shouldUseCoins will now be true
            _createGroup();
          }
          return;
        }
        setState(() => _error = msg);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _creatingGroup = false);
    }
  }

  Widget _buildLimitRow({required IconData icon, required Color color, required Color bgColor, required String label}) {
    return Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, size: 17, color: color),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))),
    ]);
  }

  Widget _profileStyleField({required IconData icon, required Widget child}) {
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
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.cyan, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(child: child),
        const SizedBox(width: 8),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(t('create_group_title'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppThemeColors.cardBg(context),
        foregroundColor: AppThemeColors.primaryText(context),
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header card with tricolor border
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                gradient: AppColors.tricolorGradient,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6)),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(19)),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _pickGroupImage,
                      child: Stack(
                        children: [
                          Container(
                            height: 52,
                            width: 52,
                            decoration: BoxDecoration(
                              gradient: _selectedImage == null
                                  ? LinearGradient(
                                      colors: _selectedColor != null
                                          ? [_selectedColor!.withValues(alpha: 0.65), _selectedColor!]
                                          : [Colors.deepPurple.shade400, Colors.deepPurple.shade800],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (_selectedColor ?? Colors.deepPurple).withValues(alpha: 0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                              image: _selectedImage != null
                                  ? DecorationImage(
                                      image: FileImage(dart_io.File(_selectedImage!.path)),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _selectedImage == null
                                ? const Icon(Icons.group, color: Colors.white, size: 28)
                                : null,
                          ),
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
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('create_new_group_title'),
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppThemeColors.primaryText(context))),
                          const SizedBox(height: 4),
                          Text(t('start_tracking_expenses_with_friends'),
                              style: TextStyle(
                                  color: AppThemeColors.secondaryText(context),
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Limit info banner
            Consumer<SessionProvider>(
              builder: (context, session, _) {
                if (session.hasFeature('group_creation')) return const SizedBox.shrink();
                final freeLeft = session.freeGroupsRemaining ?? 0;
                final dailyLeft = _dailyGroupRemaining;
                if (freeLeft <= 0 && (dailyLeft == null || dailyLeft > 0)) return const SizedBox.shrink();
                return Column(children: [
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppThemeColors.border(context)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: Column(
                      children: [
                        if (freeLeft > 0)
                          _buildLimitRow(
                            icon: Icons.card_giftcard_rounded,
                            color: Colors.green.shade600,
                            bgColor: Colors.green.withValues(alpha: 0.12),
                            label: '$freeLeft free group creation${freeLeft == 1 ? '' : 's'} remaining',
                          ),
                        if (freeLeft > 0 && dailyLeft != null) const SizedBox(height: 8),
                        if (dailyLeft != null)
                          _buildLimitRow(
                            icon: dailyLeft <= 0 ? Icons.hourglass_empty_rounded : Icons.today_rounded,
                            color: dailyLeft <= 0 ? Colors.orange.shade700 : Colors.blue.shade600,
                            bgColor: (dailyLeft <= 0 ? Colors.orange : Colors.blue).withValues(alpha: 0.12),
                            label: dailyLeft <= 0
                                ? 'Daily limit reached — resets tomorrow'
                                : 'Daily limit remaining: $dailyLeft',
                          ),
                      ],
                    ),
                  ),
                ]);
              },
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _error = null),
                      child: const Icon(Icons.close, color: Colors.red, size: 18),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 22),

            // Group title
            _profileStyleField(
              icon: Icons.title_rounded,
              child: TextField(
                controller: _titleController,
                style: TextStyle(color: AppThemeColors.primaryText(context)),
                decoration: InputDecoration(
                  labelText: t('group_title_label'),
                  labelStyle: TextStyle(color: AppThemeColors.secondaryText(context)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Group description (optional)
            _profileStyleField(
              icon: Icons.notes_rounded,
              child: TextField(
                controller: _descriptionController,
                style: TextStyle(color: AppThemeColors.primaryText(context)),
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: t('description_optional_label'),
                  hintText: t('group_description_hint'),
                  labelStyle: TextStyle(color: AppThemeColors.secondaryText(context)),
                  hintStyle: TextStyle(color: AppThemeColors.mutedText(context)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Color picker row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppThemeColors.surfaceBg(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppThemeColors.border(context)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('group_color_label'),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppThemeColors.primaryText(context))),
                        const SizedBox(height: 6),
                        Text(
                          t('pick_color_to_identify_group'),
                          style: TextStyle(
                              color: AppThemeColors.secondaryText(context),
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _pickColor,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _selectedColor ?? Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppThemeColors.border(context), width: 2),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: const Center(child: Icon(Icons.edit, color: Colors.white, size: 18)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            Text(t('add_members_by_email_label'),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 4),
            Text(
              t('invite_friends_add_expenses_pay_back'),
              style: TextStyle(
                  color: AppThemeColors.secondaryText(context), fontSize: 13),
            ),
            const SizedBox(height: 12),

            // Creator info box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppThemeColors.tinted(context,
                    light: Colors.blue.shade50, dark: const Color(0xFF1A2A3A)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppThemeColors.tinted(context,
                        light: Colors.blue.shade200,
                        dark: Colors.blue.shade700)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: AppThemeColors.tinted(context,
                          light: Colors.blue.shade700,
                          dark: Colors.blue.shade300),
                      size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t('you_creator_auto_added_to_group'),
                      style: TextStyle(
                          color: AppThemeColors.tinted(context,
                              light: Colors.blue.shade700,
                              dark: Colors.blue.shade300),
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Email input + Add button
            Row(
              children: [
                Expanded(
                  child: _profileStyleField(
                    icon: Icons.email_outlined,
                    child: TextField(
                      controller: _memberEmailController,
                      style: TextStyle(color: AppThemeColors.primaryText(context)),
                      decoration: InputDecoration(
                        hintText: t('enter_email_one_at_a_time'),
                        hintStyle: TextStyle(color: AppThemeColors.mutedText(context)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      onSubmitted: (_) => _addMemberEmail(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _addMemberEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    elevation: 4,
                  ),
                  child: Text(t('add'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),

            // Friend suggestions
            if (_friendSuggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _friendSuggestions.map((f) {
                  final email = (f['email'] ?? '').toString();
                  final name = (f['name'] ?? f['username'] ?? '').toString();
                  return Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: AppColors.tricolorGradient,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _noteColor(email.hashCode.abs() % 6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ActionChip(
                        label: Text(name.isNotEmpty ? '$name ($email)' : email),
                        onPressed: () {
                          _memberEmailController.text = email;
                          _addMemberEmail();
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                TextButton.icon(
                  onPressed: _loadingFriends ? null : _addMembersFromFriends,
                  icon: _loadingFriends
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan))
                      : const Icon(Icons.people, color: AppColors.cyan),
                  label: Text(
                    _loadingFriends ? t('loading') : t('add_from_friends_label'),
                    style: const TextStyle(color: AppColors.cyan),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _loadingGroups ? null : _addMembersFromGroups,
                  icon: _loadingGroups
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan))
                      : const Icon(Icons.group_work_rounded, color: AppColors.cyan),
                  label: Text(
                    _loadingGroups ? t('loading') : t('add_from_groups_label'),
                    style: const TextStyle(color: AppColors.cyan),
                  ),
                ),
                TextButton.icon(
                  onPressed: _addMembersFromCommunities,
                  icon: const Icon(Icons.hub_rounded, color: AppColors.cyan),
                  label: const Text('Add from Communities', style: TextStyle(color: AppColors.cyan)),
                ),
              ]),
            ),

            if (_memberAddError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_memberAddError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),

            ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Creator chip (auto-added, non-removable)
                  Builder(builder: (bCtx) {
                    final session = Provider.of<SessionProvider>(bCtx, listen: false);
                    final cEmail = (session.user?['email'] ?? '').toString();
                    final cName = (session.user?['name'] ?? '').toString().trim();
                    final cId = (session.user?['_id'] ?? '').toString();
                    final nameLabel = cName.isNotEmpty ? cName.split(' ')[0] : (cEmail.isNotEmpty ? cEmail.split('@')[0] : 'You');
                    final initials = cName.isNotEmpty ? cName[0].toUpperCase() : (cEmail.isNotEmpty ? cEmail[0].toUpperCase() : 'Y');
                    return Container(
                      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.45)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.22), shape: BoxShape.circle),
                          child: ClipOval(child: Stack(fit: StackFit.expand, children: [
                            Center(child: Text(initials, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.cyan))),
                            if (cId.isNotEmpty)
                              Image.network('${ApiConfig.baseUrl}/api/users/$cId/profile-image', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                          ])),
                        ),
                        const SizedBox(width: 6),
                        Text('$nameLabel (You)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppThemeColors.primaryText(bCtx))),
                        const SizedBox(width: 4),
                        const Icon(Icons.shield_rounded, size: 14, color: AppColors.cyan),
                      ]),
                    );
                  }),
                  ..._memberEmails.map((e) {
                  final blocked = _isBlocked(e);
                  final info = _memberUsers[e];
                  final userId = info?['_id'] ?? '';
                  final displayName = (info?['name'] ?? '').toString().trim();
                  final nameLabel = displayName.isNotEmpty ? displayName.split(' ')[0] : e.split('@')[0];
                  final initials = displayName.isNotEmpty ? displayName[0].toUpperCase() : e[0].toUpperCase();
                  return Container(
                    padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                    decoration: BoxDecoration(
                      color: blocked ? Colors.red.shade50 : AppColors.cyan.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: blocked ? Colors.red.shade300 : AppColors.cyan.withValues(alpha: 0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: blocked ? Colors.red.shade100 : AppColors.cyan.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(child: Stack(fit: StackFit.expand, children: [
                          Center(child: Text(initials, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: blocked ? Colors.red : AppColors.cyan))),
                          if (userId.isNotEmpty && !blocked)
                            Image.network('${ApiConfig.baseUrl}/api/users/$userId/profile-image', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                        ])),
                      ),
                      const SizedBox(width: 6),
                      Text(nameLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: blocked ? Colors.red.shade700 : AppThemeColors.primaryText(context))),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _removeMemberEmail(e),
                        child: Icon(Icons.close_rounded, size: 16, color: blocked ? Colors.red.shade400 : AppThemeColors.mutedText(context)),
                      ),
                    ]),
                  );
                }).toList(),
                ],
              ),
            ],

            const SizedBox(height: 20),

            // Community picker
            GestureDetector(
              onTap: _showCommunityPicker,
              child: _profileStyleField(
                icon: Icons.hub_rounded,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: _selectedCommunityIds.isEmpty
                          ? Text('Add to Communities (optional)', style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 15))
                          : Wrap(
                              spacing: 6, runSpacing: 4,
                              children: _selectedCommunityIds.map((id) {
                                final name = _selectedCommunityNames[id] ?? 'Community';
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.cyan)),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () => setState(() { _selectedCommunityIds.remove(id); _selectedCommunityNames.remove(id); }),
                                      child: const Icon(Icons.close_rounded, size: 14, color: AppColors.cyan),
                                    ),
                                  ]),
                                );
                              }).toList(),
                            ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.expand_more_rounded, size: 20, color: AppThemeColors.mutedText(context)),
                  ]),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Create button with limits info
            Consumer<SessionProvider>(
              builder: (context, session, _) {
                final dailyLimitReached = !session.hasFeature('group_creation') &&
                    _dailyGroupRemaining != null &&
                    _dailyGroupRemaining! <= 0;
                final canCreate = session.hasFeature('group_creation') ||
                    (!dailyLimitReached && (session.freeGroupsRemaining ?? 0) > 0) ||
                    (session.lenDenCoins ?? 0) >= 20;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: _creatingGroup || !canCreate ? null : _createGroup,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 4,
                      ),
                      child: _creatingGroup
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(t('create_group_title'), style: const TextStyle(fontSize: 18, color: Colors.white)),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
