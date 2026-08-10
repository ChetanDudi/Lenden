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

class CreateGroupPage extends StatefulWidget {
  final List<String>? prefillMemberEmails;
  final bool useCoins;

  const CreateGroupPage({Key? key, this.prefillMemberEmails, this.useCoins = false}) : super(key: key);

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final _titleController = TextEditingController();
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
    setState(() => _loadingFriends = true);
    try {
      final res = await ApiClient.get('/api/friends');
      if (!mounted) return;
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      final friends = List<Map<String, dynamic>>.from(data['friends'] ?? []);
      final blocked = List<Map<String, dynamic>>.from(data['blockedUsers'] ?? []);
      _blockedEmails = blocked
          .map((u) => (u['email'] ?? '').toString().toLowerCase().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      if (!mounted) return;

      final tempSelected = Set<String>.from(_memberEmails);
      final selectableCount = friends
          .where((f) => !_isBlocked((f['email'] ?? '').toString().toLowerCase().trim()))
          .length;
      bool selectAll = tempSelected.length == selectableCount && selectableCount > 0;

      await showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: StatefulBuilder(
            builder: (context, setDialogState) => Container(
              padding: const EdgeInsets.all(16),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: AppColors.tricolorGradient,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      Text(t('select_friends_title'),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppThemeColors.primaryText(context))),
                      const SizedBox(height: 8),
                      if (friends.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Checkbox(
                                value: selectAll,
                                onChanged: (val) {
                                  setDialogState(() {
                                    if (val == true) {
                                      tempSelected
                                        ..clear()
                                        ..addAll(friends
                                            .where((f) => !_isBlocked(
                                                (f['email'] ?? '').toString().toLowerCase().trim()))
                                            .map((f) => (f['email'] ?? '').toString()));
                                      selectAll = true;
                                    } else {
                                      tempSelected.clear();
                                      selectAll = false;
                                    }
                                  });
                                },
                              ),
                              Text(t('select_all_label'),
                                  style: TextStyle(color: AppThemeColors.primaryText(context))),
                              const Spacer(),
                              TextButton(
                                onPressed: () {
                                  setDialogState(() {
                                    tempSelected.clear();
                                    selectAll = false;
                                  });
                                },
                                child: Text(t('deselect_all_label')),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: friends.isEmpty
                            ? Center(
                                child: Text(t('no_friends_found_label'),
                                    style: TextStyle(color: AppThemeColors.secondaryText(context))))
                            : ListView.builder(
                                itemCount: friends.length,
                                itemBuilder: (context, index) {
                                  final f = friends[index];
                                  final email = (f['email'] ?? '').toString();
                                  final name = (f['name'] ?? f['username'] ?? '').toString();
                                  final isBlocked = _isBlocked(email);
                                  final selected = tempSelected.contains(email);
                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isBlocked
                                          ? AppThemeColors.surfaceBg(context)
                                          : AppThemeColors.tinted(context,
                                              light: _noteColor(index),
                                              dark: _noteColor(index).withValues(alpha: 0.22)),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: selected ? Colors.blue : Colors.transparent),
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: isBlocked ? Colors.grey : Colors.blue.shade100,
                                        child: Text(
                                          name.isNotEmpty ? name[0].toUpperCase() : email[0].toUpperCase(),
                                          style: TextStyle(color: isBlocked ? Colors.grey : Colors.blue),
                                        ),
                                      ),
                                      title: Text(name.isNotEmpty ? name : email,
                                          style: TextStyle(color: AppThemeColors.primaryText(context))),
                                      subtitle: name.isNotEmpty
                                          ? Text(email,
                                              style: TextStyle(color: AppThemeColors.secondaryText(context)))
                                          : null,
                                      trailing: isBlocked
                                          ? Text(t('blocked_label'),
                                              style: const TextStyle(color: Colors.red, fontSize: 12))
                                          : Checkbox(
                                              value: selected,
                                              onChanged: (val) {
                                                setDialogState(() {
                                                  if (val == true) {
                                                    tempSelected.add(email);
                                                  } else {
                                                    tempSelected.remove(email);
                                                  }
                                                  selectAll = tempSelected.length == selectableCount;
                                                });
                                              },
                                            ),
                                      onTap: isBlocked
                                          ? null
                                          : () {
                                              setDialogState(() {
                                                if (selected) {
                                                  tempSelected.remove(email);
                                                } else {
                                                  tempSelected.add(email);
                                                }
                                                selectAll = tempSelected.length == selectableCount;
                                              });
                                            },
                                    ),
                                  );
                                },
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(t('done')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      if (mounted) {
        setState(() => _memberEmails = tempSelected.toList());
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingFriends = false);
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
                              gradient: LinearGradient(
                                colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade800],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.deepPurple.withValues(alpha: 0.25),
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
