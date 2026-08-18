import 'package:elegant_notification/elegant_notification.dart';
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../../widgets/stylish_dialog.dart';
import '../../digitise/gift_card_page.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io' as dart_io;
import '../../../utils/avatar_helpers.dart' as ah;

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
    setState(() {
      _memberEmails.add(email);
      _memberEmailController.clear();
    });
  }

  void _removeMemberEmail(String email) {
    setState(() => _memberEmails.remove(email));
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
      setState(() => _memberEmails = tempSelected.toList());
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
          Navigator.pop(context, data['group']);
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
          Navigator.pop(context, data['group']);
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: AppThemeColors.border(context), width: 1.5),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.cyan, width: 2),
    );
    final decoration = InputDecoration(
      filled: true,
      fillColor: AppThemeColors.surfaceBg(context),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: focusedBorder,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    );

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
            TextField(
              controller: _titleController,
              style: TextStyle(color: AppThemeColors.primaryText(context)),
              decoration: decoration.copyWith(
                labelText: t('group_title_label'),
                prefixIcon: Icon(Icons.title,
                    color: AppThemeColors.secondaryText(context)),
              ),
            ),

            const SizedBox(height: 14),

            // Group description (optional)
            TextField(
              controller: _descriptionController,
              style: TextStyle(color: AppThemeColors.primaryText(context)),
              maxLines: 2,
              decoration: decoration.copyWith(
                labelText: 'Description (optional)',
                hintText: 'What is this group for?',
                prefixIcon: Icon(Icons.notes_rounded,
                    color: AppThemeColors.secondaryText(context)),
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
                  child: TextField(
                    controller: _memberEmailController,
                    style: TextStyle(color: AppThemeColors.primaryText(context)),
                    decoration: decoration.copyWith(
                      hintText: t('enter_email_one_at_a_time'),
                      prefixIcon: Icon(Icons.email_outlined,
                          color: AppThemeColors.secondaryText(context)),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onSubmitted: (_) => _addMemberEmail(),
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
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _loadingFriends ? null : _addMembersFromFriends,
                icon: _loadingFriends
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan),
                      )
                    : const Icon(Icons.people, color: AppColors.cyan),
                label: Text(
                  _loadingFriends ? 'Loading...' : t('add_from_friends_label'),
                  style: const TextStyle(color: AppColors.cyan),
                ),
              ),
            ),

            if (_memberAddError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_memberAddError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),

            if (_memberEmails.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _memberEmails.map((e) {
                  final blocked = _isBlocked(e);
                  return Chip(
                    avatar: blocked ? const Icon(Icons.block_rounded, size: 14, color: Colors.red) : null,
                    label: Text(e, style: TextStyle(fontSize: 13, color: blocked ? Colors.red.shade700 : null)),
                    onDeleted: () => _removeMemberEmail(e),
                    backgroundColor: blocked ? Colors.red.shade50 : Colors.blue.shade50,
                    side: blocked ? BorderSide(color: Colors.red.shade300) : null,
                    deleteIconColor: Colors.red.shade300,
                  );
                }).toList(),
              ),
            ],

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
                    if (!session.hasFeature('group_creation') && (session.freeGroupsRemaining ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          t('free_group_creations_remaining').replaceFirst(
                              '{count}', '${session.freeGroupsRemaining}'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.green),
                        ),
                      ),
                    if (!session.hasFeature('group_creation') && _dailyGroupRemaining != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          t('daily_limit_remaining_label').replaceFirst(
                              '{count}', '$_dailyGroupRemaining'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.orange),
                        ),
                      ),
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
