import 'package:elegant_notification/elegant_notification.dart';
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../../widgets/stylish_dialog.dart';
import '../../digitise/subscriptions_page.dart';
import '../../digitise/gift_card_page.dart';

const _tricolorGradient = LinearGradient(
  colors: [Color(0xFFFF9933), Color(0xFFFFFFFF), Color(0xFF138808)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class CreateGroupPage extends StatefulWidget {
  final List<String>? prefillMemberEmails;

  const CreateGroupPage({Key? key, this.prefillMemberEmails}) : super(key: key);

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
    if (session.isSubscribed) return;
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
    final email = _memberEmailController.text.trim();
    if (email.isEmpty) return;
    setState(() => _memberAddError = null);

    final currentEmail =
        Provider.of<SessionProvider>(context, listen: false).user?['email'];
    if (email.toLowerCase() == (currentEmail ?? '').toLowerCase()) {
      setState(() {
        _memberAddError = 'You (group creator) are already added by default.';
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
        _memberAddError = 'This user is already added to the group.';
        _memberEmailController.clear();
      });
      return;
    }
    final exists = await _userExists(email);
    if (!exists) {
      setState(() => _memberAddError = 'This user does not exist, can\'t add.');
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
    try {
      final res = await ApiClient.get('/api/friends');
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
                  gradient: _tricolorGradient,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: _noteColor(0),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      const Text('Select Friends', style: TextStyle(fontWeight: FontWeight.bold)),
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
                              const Text('Select All'),
                              const Spacer(),
                              TextButton(
                                onPressed: () {
                                  setDialogState(() {
                                    tempSelected.clear();
                                    selectAll = false;
                                  });
                                },
                                child: const Text('Deselect All'),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: friends.isEmpty
                            ? const Center(child: Text('No friends found'))
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
                                      color: isBlocked ? Colors.grey.shade100 : _noteColor(index),
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
                                      title: Text(name.isNotEmpty ? name : email),
                                      subtitle: name.isNotEmpty ? Text(email) : null,
                                      trailing: isBlocked
                                          ? const Text('Blocked', style: TextStyle(color: Colors.red, fontSize: 12))
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
                          child: const Text('Done'),
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
    } catch (_) {}
  }

  Future<void> _pickColor() async {
    Color picked = _selectedColor ?? Colors.blue;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick Group Color'),
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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() => _selectedColor = picked);
              Navigator.of(context).pop();
            },
            child: const Text('Select'),
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
              title: const Text('Congratulations!'),
              description: const Text("You've won a gift card!"),
              action: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GiftCardPage())),
                child: const Text('View', style: TextStyle(color: Colors.blue)),
              ),
            ).show(context);
          } else {
            ElegantNotification.success(
              title: const Text('Success'),
              description: const Text('Group has been successfully created!'),
            ).show(context);
          }
          Navigator.pop(context, data['group']);
        }
      } else if (res.statusCode == 403) {
        final msg = (data['error'] ?? 'Forbidden').toString();
        if (msg.toLowerCase().contains('blocked')) {
          showBlockedUserDialog(context, message: msg);
        } else {
          showInsufficientCoinsDialog(context);
        }
      } else if (res.statusCode == 429) {
        showDailyLimitDialog(context, message: (data['error'] ?? 'Daily limit reached').toString());
      } else {
        setState(() => _error = data['error'] ?? 'Failed to create group');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _creatingGroup = false);
    }
  }

  Future<void> _createGroup() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final dailyLimitExceeded = !session.isSubscribed &&
        _dailyGroupRemaining != null &&
        _dailyGroupRemaining! <= 0;
    final shouldUseCoins = !session.isSubscribed &&
        (dailyLimitExceeded || (session.freeGroupsRemaining ?? 0) <= 0);

    if (_hasBlockedMembers()) {
      showBlockedUserDialog(context);
      return;
    }

    if (shouldUseCoins) {
      if ((session.lenDenCoins ?? 0) < 20) {
        (session.lenDenCoins ?? 0) == 0
            ? showZeroCoinsDialog(context)
            : showInsufficientCoinsDialog(context);
        return;
      }
      final useCoins = await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: _tricolorGradient,
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.monetization_on, color: Colors.orange, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Use LenDen Coins',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    dailyLimitExceeded
                        ? 'Your daily group creation limit is finished. You can still create this group now by spending 20 LenDen coins.'
                        : 'You have no free groups remaining. Would you like to use 20 LenDen coins to create this group?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                  ),
                  if (dailyLimitExceeded) ...[
                    const SizedBox(height: 12),
                    Text(
                      "Warning: this will bypass today's free daily limit.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.orange[800], fontWeight: FontWeight.w700),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text('OR', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.orange)),
                  const SizedBox(height: 8),
                  const Text(
                    'Subscribe now for unlimited access',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.green, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[300],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        child: Text('Cancel', style: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context, false);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => SubscriptionsPage()));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        child: const Text('Subscribe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        child: const Text('Use Coins', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
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
              title: const Text('Congratulations!'),
              description: const Text("You've won a gift card!"),
              action: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GiftCardPage())),
                child: const Text('View', style: TextStyle(color: Colors.blue)),
              ),
            ).show(context);
          } else {
            ElegantNotification.success(
              title: const Text('Success'),
              description: const Text('Group has been successfully created!'),
            ).show(context);
          }
          Navigator.pop(context, data['group']);
        }
      } else {
        final msg = (data['error'] ?? 'Failed to create group').toString();
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
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.cyan, width: 2),
    );
    final decoration = InputDecoration(
      filled: true,
      fillColor: Colors.grey.shade50,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: focusedBorder,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      appBar: AppBar(
        title: const Text('Create Group', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
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
                gradient: _tricolorGradient,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6)),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(19)),
                child: Row(
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
                      ),
                      child: const Icon(Icons.group, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Create New Group', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('Start tracking expenses with friends', style: TextStyle(color: Colors.grey, fontSize: 13)),
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
              decoration: decoration.copyWith(
                labelText: 'Group Title',
                prefixIcon: Icon(Icons.title, color: Colors.grey[700]),
              ),
            ),

            const SizedBox(height: 16),

            // Color picker row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Group Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 6),
                        Text(
                          'Pick a color to identify this group in lists and tables.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
                        border: Border.all(color: Colors.grey.shade300, width: 2),
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

            const Text('Add Members (by email)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              'Invite friends so they can add expenses and pay back.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 12),

            // Creator info box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You (group creator) will be automatically added to the group.',
                      style: TextStyle(color: Colors.blue.shade700, fontSize: 13, fontWeight: FontWeight.w500),
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
                    decoration: decoration.copyWith(
                      hintText: 'Enter email (one at a time)',
                      prefixIcon: Icon(Icons.email_outlined, color: Colors.grey[700]),
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
                  child: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
                      gradient: _tricolorGradient,
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
                onPressed: _addMembersFromFriends,
                icon: const Icon(Icons.people, color: AppColors.cyan),
                label: const Text('Add from Friends', style: TextStyle(color: AppColors.cyan)),
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
                children: _memberEmails.map((e) => Chip(
                  label: Text(e, style: const TextStyle(fontSize: 13)),
                  onDeleted: () => _removeMemberEmail(e),
                  backgroundColor: Colors.blue.shade50,
                  deleteIconColor: Colors.red.shade300,
                )).toList(),
              ),
            ],

            const SizedBox(height: 30),

            // Create button with limits info
            Consumer<SessionProvider>(
              builder: (context, session, _) {
                final dailyLimitReached = !session.isSubscribed &&
                    _dailyGroupRemaining != null &&
                    _dailyGroupRemaining! <= 0;
                final canCreate = session.isSubscribed ||
                    (!dailyLimitReached && (session.freeGroupsRemaining ?? 0) > 0) ||
                    (session.lenDenCoins ?? 0) >= 20;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!session.isSubscribed && (session.freeGroupsRemaining ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${session.freeGroupsRemaining} free group creations remaining.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.green),
                        ),
                      ),
                    if (!session.isSubscribed && _dailyGroupRemaining != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Daily limit remaining: $_dailyGroupRemaining',
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
                          : const Text('Create Group', style: TextStyle(fontSize: 18, color: Colors.white)),
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
