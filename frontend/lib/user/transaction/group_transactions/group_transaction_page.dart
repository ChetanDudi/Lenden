import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import '../../../widgets/wave_widget.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import 'group_detail_page.dart';
import '../../chats/group_chat_page.dart';
import 'create_group_page.dart';
import '../../../widgets/stylish_dialog.dart';
import '../../../widgets/app_widgets.dart';
import '../../../utils/responsive.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/budget_limit_banner.dart';
import '../../../widgets/search_tab_bar.dart';
import '../../../widgets/free_attempts_banner.dart';
import '../../budget/budget_messages_page.dart';
import '../../budget/budget_planning_page.dart';
import 'package:image_picker/image_picker.dart';
import '../../../utils/image_picker_utils.dart';
import '../../../utils/community_helpers.dart';

class GroupTransactionPage extends StatefulWidget {
  final List<String>? prefillMemberEmails;
  final bool initialShowFavouritesOnly;

  const GroupTransactionPage({
    Key? key,
    this.prefillMemberEmails,
    this.initialShowFavouritesOnly = false,
  }) : super(key: key);
  @override
  State<GroupTransactionPage> createState() => _GroupTransactionPageState();
}

class _GroupTransactionPageState extends State<GroupTransactionPage> {
  // State for group creation
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _memberEmailController = TextEditingController();
  List<String> memberEmails = [];
  bool creatingGroup = false;
  String? error;
  bool loading = false;
  String? memberAddError;

  // State for group details
  Map<String, dynamic>? group; // Real group data
  bool isCreator = false; // Real logic
  String? userEmail; // For permissions

  final TextEditingController _groupSearchCtrl = TextEditingController();

  List<Map<String, dynamic>> userGroups = [];
  List<Map<String, dynamic>> filteredGroups = [];
  bool groupsLoading = true;
  String groupSearchQuery = '';
  String groupFilter = 'all'; // all, created, member
  String groupSort =
      'newest'; // newest, oldest, name_az, name_za, members_high, members_low
  String memberCountFilter = 'all'; // all, 2-5, 6-10, 10+
  String dateFilter = 'all'; // all, 7days, 30days, custom
  String _memberEmailFilter = 'all';
  DateTime? customStartDate;
  DateTime? customEndDate;
  Color? selectedGroupColor; // for group color customization
  bool _showFavouritesOnly = false;

  // Budget spending per group: groupId → {spent, budget}
  Map<String, Map<String, dynamic>> _groupBudgetSpending = {};
  bool _budgetStatusLoading = true;
  int _bannerRefreshTrigger = 0;
  String? _uploadingImageGroupId;

  @override
  void initState() {
    super.initState();
    _showFavouritesOnly = widget.initialShowFavouritesOnly;
    if (widget.prefillMemberEmails != null &&
        widget.prefillMemberEmails!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showCreateGroup(prefill: widget.prefillMemberEmails);
      });
    }
    _fetchUserGroups();
    _fetchGroupBudgetStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<SessionProvider>(context, listen: false)
            .loadFreebieCounts();
      }
    });
  }









  @override
  void dispose() {
    _titleController.dispose();
    _memberEmailController.dispose();
    _groupSearchCtrl.dispose();
    super.dispose();
  }




  // Initialize selected members for expense (start with no members selected)

  // Initialize custom split amounts for selected members

  // Get total amount entered for custom split

  // Get remaining amount for custom split

  Widget _gtImgPlaceholder(Color color, String title) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, Color.lerp(color, Colors.black, 0.4)!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Text(
            title.isNotEmpty ? title[0].toUpperCase() : 'G',
            style: const TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.w900,
              color: Colors.white38,
              height: 1,
            ),
          ),
        ),
      );

  Future<void> _fetchGroupBudgetStatus() async {
    try {
      final res = await ApiClient.get('/api/budget/status');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final spending = List<dynamic>.from(data['groupSpending'] ?? []);
        final map = <String, Map<String, dynamic>>{};
        for (final g in spending) {
          if (g is Map) {
            final id = g['id']?.toString() ?? '';
            if (id.isNotEmpty) map[id] = Map<String, dynamic>.from(g);
          }
        }
        if (mounted) setState(() { _groupBudgetSpending = map; _budgetStatusLoading = false; });
      } else {
        if (mounted) setState(() => _budgetStatusLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _budgetStatusLoading = false);
    }
  }









  // Calculate member's total split amount from all expenses in the group (excluding settled amounts)

  // Calculate current user's total split amount from all expenses in the group










  Future<void> _fetchUserGroups() async {
    setState(() {
      groupsLoading = true;
      error = null;
    });
    try {
      final res = await ApiClient.get('/api/group-transactions/user-groups');

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final loaded =
            List<Map<String, dynamic>>.from(data['groups'] ?? []);
        userGroups = loaded;
        _filterAndSearchGroups(); // populate filteredGroups while groupsLoading is still true
        setState(() {
          groupsLoading = false;
        });
      } else {
        final t = AppLocalizations.of(context).t;
        setState(() {
          error =
              t('failed_to_load_groups_retry_message');
          groupsLoading = false;
        });
      }
    } catch (e) {
      final t = AppLocalizations.of(context).t;
      setState(() {
        error = t('unable_to_connect_check_internet_message');
        groupsLoading = false;
      });
    }
  }

  void _showCreateGroupFiltersSheet() {
    final t = AppLocalizations.of(context).t;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.filter_list, color: AppColors.cyan),
                          const SizedBox(width: 8),
                          Text(t('filters_label'),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          t('show_favourites_only_label'),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.cyan),
                        ),
                        value: _showFavouritesOnly,
                        activeColor: AppColors.cyan,
                        onChanged: (value) {
                          setState(() => _showFavouritesOnly = value);
                          setSheetState(() {});
                          _filterAndSearchGroups();
                        },
                      ),
                      const Divider(),
                      _filterDropdownRow<String>(
                        label: t('group_label'),
                        value: groupFilter,
                        items: {
                          'all': t('filter_all_label'),
                          'created': t('created_by_me_label'),
                          'member': t('member_label'),
                        },
                        onChanged: (val) {
                          setState(() => groupFilter = val);
                          setSheetState(() {});
                          _filterAndSearchGroups();
                        },
                      ),
                      _filterDropdownRow<String>(
                        label: t('sort_label'),
                        value: groupSort,
                        items: {
                          'newest': t('newest_label'),
                          'oldest': t('oldest_label'),
                          'name_az': t('name_a_z_label'),
                          'name_za': t('name_z_a_label'),
                          'members_high': t('members_high_low_label'),
                          'members_low': t('members_low_high_label'),
                        },
                        onChanged: (val) {
                          setState(() => groupSort = val);
                          setSheetState(() {});
                          _filterAndSearchGroups();
                        },
                      ),
                      _filterDropdownRow<String>(
                        label: t('members_label'),
                        value: memberCountFilter,
                        items: {
                          'all': t('all_members_label'),
                          '2-5': '2-5',
                          '6-10': '6-10',
                          '10+': '10+',
                        },
                        onChanged: (val) {
                          setState(() => memberCountFilter = val);
                          setSheetState(() {});
                          _filterAndSearchGroups();
                        },
                      ),
                      _filterDropdownRow<String>(
                        label: t('created_label'),
                        value: dateFilter,
                        items: {
                          'all': t('all_dates_label'),
                          '7days': t('last_7_days_label'),
                          '30days': t('last_30_days_label'),
                          'custom': t('custom_label'),
                        },
                        onChanged: (val) async {
                          setState(() => dateFilter = val);
                          setSheetState(() {});
                          if (val == 'custom') {
                            final picked = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setState(() {
                                customStartDate = picked.start;
                                customEndDate = picked.end;
                              });
                            }
                          }
                          _filterAndSearchGroups();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _filterDropdownRow<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required void Function(T) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          DropdownButton<T>(
            value: value,
            borderRadius: BorderRadius.circular(16),
            style: const TextStyle(
                color: AppColors.cyan, fontWeight: FontWeight.bold),
            underline: Container(),
            items: items.entries
                .map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (val) {
              if (val != null) onChanged(val);
            },
          ),
        ],
      ),
    );
  }

  void _filterAndSearchGroups() {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final myEmail = session.user?['email'] ?? '';
    List<Map<String, dynamic>> temp = userGroups.where((g) {
      if (_showFavouritesOnly) {
        final isFavourite = (g['favourite'] as List? ?? []).contains(myEmail);
        if (!isFavourite) return false;
      }

      // Member email filter
      if (_memberEmailFilter != 'all') {
        final hasMember = (g['members'] as List? ?? []).any(
          (m) => m is Map && (m['email'] ?? '').toString() == _memberEmailFilter);
        if (!hasMember) return false;
      }

      final title = (g['title'] ?? '').toString().toLowerCase();
      final creatorEmail =
          (g['creator']?['email'] ?? '').toString().toLowerCase();
      final matchesSearch = groupSearchQuery.isEmpty ||
          title.contains(groupSearchQuery.toLowerCase()) ||
          creatorEmail.contains(groupSearchQuery.toLowerCase());
      final isCreator = creatorEmail == myEmail.toLowerCase();
      final isMember = (g['members'] as List).any(
          (m) => (m['email'] ?? '').toLowerCase() == myEmail.toLowerCase());
      if (groupFilter == 'created') return matchesSearch && isCreator;
      if (groupFilter == 'member')
        return matchesSearch && !isCreator && isMember;
      // Advanced filters
      final memberCount = (g['members'] as List).length;
      if (memberCountFilter == '2-5' && (memberCount < 2 || memberCount > 5))
        return false;
      if (memberCountFilter == '6-10' && (memberCount < 6 || memberCount > 10))
        return false;
      if (memberCountFilter == '10+' && memberCount < 11) return false;
      if (dateFilter == '7days') {
        final created =
            DateTime.tryParse(g['createdAt'] ?? '') ?? DateTime(2000);
        if (created.isBefore(DateTime.now().subtract(Duration(days: 7))))
          return false;
      }
      if (dateFilter == '30days') {
        final created =
            DateTime.tryParse(g['createdAt'] ?? '') ?? DateTime(2000);
        if (created.isBefore(DateTime.now().subtract(Duration(days: 30))))
          return false;
      }
      if (dateFilter == 'custom' &&
          customStartDate != null &&
          customEndDate != null) {
        final created =
            DateTime.tryParse(g['createdAt'] ?? '') ?? DateTime(2000);
        if (created.isBefore(customStartDate!) ||
            created.isAfter(customEndDate!)) return false;
      }
      return matchesSearch;
    }).toList();
    // Sorting (same as before)
    temp.sort((a, b) {
      switch (groupSort) {
        case 'oldest':
          return (a['createdAt'] ?? '').compareTo(b['createdAt'] ?? '');
        case 'name_az':
          return (a['title'] ?? '')
              .toLowerCase()
              .compareTo((b['title'] ?? '').toLowerCase());
        case 'name_za':
          return (b['title'] ?? '')
              .toLowerCase()
              .compareTo((a['title'] ?? '').toLowerCase());
        case 'members_high':
          return (b['members'] as List)
              .length
              .compareTo((a['members'] as List).length);
        case 'members_low':
          return (a['members'] as List)
              .length
              .compareTo((b['members'] as List).length);
        case 'newest':
        default:
          return (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? '');
      }
    });
    setState(() {
      filteredGroups = temp;
    });
  }

  void _showGroupDetails(Map<String, dynamic> g) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupDetailPage(
          groupId: g['_id'].toString(),
          initialGroup: g,
        ),
      ),
    ).then((_) {
      _fetchUserGroups();
      if (mounted) setState(() => _bannerRefreshTrigger++);
    });
  }

  Color _colorFromGroup(Map<String, dynamic> g) {
    if (g['color'] != null) {
      try {
        return Color(int.parse(g['color'].toString().replaceFirst('#', '0xff')));
      } catch (_) {}
    }
    return Colors.blue.shade300;
  }

  Future<void> _pickGroupImageFromCard(Map<String, dynamic> g) async {
    final gId = g['_id']?.toString() ?? '';
    final hasImage = g['groupImageUrl'] != null && g['groupImageUrl'].toString().isNotEmpty;
    final currentColor = _colorFromGroup(g);
    const presetColors = [
      Colors.teal, Colors.deepPurple, Colors.indigo, Colors.blue,
      Colors.green, Colors.orange, Colors.pink, Colors.red,
      Colors.brown, Colors.blueGrey,
    ];

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
            if (hasImage)
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
              children: presetColors.map((c) => GestureDetector(
                onTap: () => Navigator.pop(ctx, 'color:${c.toARGB32()}'),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c.toARGB32() == currentColor.toARGB32() ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 4)],
                  ),
                  child: c.toARGB32() == currentColor.toARGB32()
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
      setState(() => _uploadingImageGroupId = gId);
      try {
        final res = await ApiClient.delete('/api/group-transactions/$gId/image');
        if (res.statusCode == 200 && mounted) {
          final idx = userGroups.indexWhere((x) => x['_id']?.toString() == gId);
          if (idx != -1) userGroups[idx] = {...userGroups[idx], 'groupImageUrl': null};
          _filterAndSearchGroups();
        }
      } finally {
        if (mounted) setState(() => _uploadingImageGroupId = null);
      }
      return;
    }

    if (action != null && action.startsWith('color:')) {
      final colorInt = int.tryParse(action.substring(6));
      if (colorInt == null) return;
      final hexColor = '#${colorInt.toRadixString(16).substring(2).toUpperCase()}';
      final res = await ApiClient.put('/api/group-transactions/$gId/color', body: {'color': hexColor});
      if (res.statusCode == 200 && mounted) {
        final idx = userGroups.indexWhere((x) => x['_id']?.toString() == gId);
        if (idx != -1) userGroups[idx] = {...userGroups[idx], 'color': hexColor};
        _filterAndSearchGroups();
      }
      return;
    }

    if (action == null) return;

    final result = await ImagePickerUtils.pickAndCrop(
      context,
      source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
    );
    if (result == null || !mounted) return;

    setState(() => _uploadingImageGroupId = gId);
    try {
      final res = await ApiClient.putMultipart(
        '/api/group-transactions/$gId/image',
        files: [ApiMultipartFile(field: 'groupImage', filename: result.file.name, bytes: result.bytes)],
      );
      if (res.statusCode == 200 && mounted) {
        final data = json.decode(res.body);
        final newUrl = data['groupImageUrl']?.toString();
        final idx = userGroups.indexWhere((x) => x['_id']?.toString() == gId);
        if (idx != -1) userGroups[idx] = {...userGroups[idx], 'groupImageUrl': newUrl};
        _filterAndSearchGroups();
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _uploadingImageGroupId = null);
    }
  }

  Future<void> _toggleFavourite(String groupId) async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final email = (session.user?['email'] ?? '').toString();
    if (email.isEmpty) return;
    final idx = userGroups.indexWhere((g) => g['_id']?.toString() == groupId);
    if (idx == -1) return;
    final group = userGroups[idx];
    final favList = List<dynamic>.from(group['favourite'] as List? ?? []);
    group['favourite'] = favList;
    final isFav = favList.contains(email);
    setState(() {
      if (isFav) favList.remove(email); else favList.add(email);
    });
    _filterAndSearchGroups();
    try {
      final response = await ApiClient.put(
        '/api/group-transactions/$groupId/favourite',
        body: {'email': email},
      );
      if (response.statusCode != 200) {
        setState(() {
          if (isFav) favList.add(email); else favList.remove(email);
        });
        _filterAndSearchGroups();
      }
    } catch (_) {
      setState(() {
        if (isFav) favList.add(email); else favList.remove(email);
      });
      _filterAndSearchGroups();
    }
  }

  Future<void> _showJoinByCodeDialog() async {
    final t = AppLocalizations.of(context).t;
    final codeController = TextEditingController();
    bool joining = false;

    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: AppColors.tricolorGradient,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(ctx),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0077B6), AppColors.cyan],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.cyan.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.group_add_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t('join_group_by_code_title'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppThemeColors.primaryText(ctx),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enter the invite code shared by your group creator',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppThemeColors.secondaryText(ctx),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cyan.withValues(alpha: 0.45), width: 1.5),
                      color: AppColors.cyan.withValues(alpha: 0.05),
                    ),
                    child: TextField(
                      controller: codeController,
                      textCapitalization: TextCapitalization.characters,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6,
                        color: AppColors.cyan,
                      ),
                      decoration: InputDecoration(
                        hintText: t('enter_join_code_hint'),
                        hintStyle: TextStyle(
                          fontSize: 14,
                          letterSpacing: 1,
                          fontWeight: FontWeight.normal,
                          color: AppThemeColors.mutedText(ctx),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: joining
                          ? null
                          : () async {
                              final code = codeController.text.trim();
                              if (code.isEmpty) return;
                              setDialog(() => joining = true);
                              final res = await ApiClient.post(
                                '/api/group-transactions/join',
                                body: {'joinCode': code},
                              );
                              if (!mounted) return;
                              Navigator.pop(ctx);
                              if (res.statusCode == 200) {
                                showSnack(context, t('join_group_success'));
                                _fetchUserGroups();
                              } else {
                                final err = jsonDecode(res.body)['error'] ?? t('something_went_wrong');
                                showSnack(context, err.toString(), isError: true);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: joining
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(t('join_group_button'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(t('cancel'), style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    codeController.dispose();
  }

  Future<void> _showCreateGroup({List<String>? prefill}) async {
    final t = AppLocalizations.of(context).t;
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('group_creation')) {
      int? dailyRemaining;
      await Future.wait([
        session.loadFreebieCounts(),
        ApiClient.get('/api/limits/daily').then((res) {
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            dailyRemaining = data['limits']?['groups']?['remaining'];
          }
        }),
      ]);
      if (!mounted) return;
      if (dailyRemaining != null && dailyRemaining! <= 0) {
        showDailyLimitDialog(context,
            message: t('daily_group_creation_limit_reached_message'));
        return;
      }
      final freeRemaining = session.freeGroupsRemaining ?? 0;
      if (freeRemaining <= 0) {
        final coins = session.lenDenCoins ?? 0;
        final useCoins = await showFreeAttemptsExhaustedDialog(context,
            featureName: t('group_creation_feature_label'), coinCost: session.groupCreationCoinCost, currentCoins: coins);
        if (!mounted) return;
        if (useCoins != true) return;
        final result = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  CreateGroupPage(prefillMemberEmails: prefill, useCoins: true)),
        );
        if (!mounted) return;
        _fetchUserGroups();
        if (result != null) _showGroupDetails(result);
        return;
      }
    }
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateGroupPage(prefillMemberEmails: prefill),
      ),
    );
    if (!mounted) return;
    _fetchUserGroups();
    if (result != null) _showGroupDetails(result);
  }

























  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      body: Stack(
        children: [
          // Wavy blue background at the top (header/banner only)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: const DeeperTopWaveClipper(),
              child: Container(
                height: context.sh(70),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.cyan, Color(0xFF48CAE4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                    onPressed: () => Navigator.pushReplacementNamed(
                        context, '/user/dashboard'),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        group == null
                            ? t('group_transactions_title_label')
                            : t('group_colon_label').replaceFirst('{title}', group?['title'] ?? ''),
                        style: TextStyle(
                          color: AppThemeColors.primaryText(context),
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          shadows: const [Shadow(color: Colors.black26, blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.link_rounded, color: AppThemeColors.primaryText(context)),
                    tooltip: t('join_group_by_code_title'),
                    onPressed: _showJoinByCodeDialog,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 80),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: groupsLoading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null && userGroups.isEmpty
                      ? errorStateWidget(context, error!, _fetchUserGroups)
                  : userGroups.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(28),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [Color(0xFFE0F7FA), Color(0xFFB2EBF2)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.group_rounded, size: 72, color: AppColors.cyan),
                                    ),
                                    const SizedBox(height: 24),
                                    Text(
                                      t('no_groups_yet_message'),
                                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.cyan),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      t('split_expenses_with_friends_message'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 15, color: Colors.grey[600], height: 1.5),
                                    ),
                                    const SizedBox(height: 28),
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: AppColors.tricolorGradientColors,
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                        ),
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      padding: const EdgeInsets.all(2),
                                      child: ElevatedButton.icon(
                                        onPressed: _showCreateGroup,
                                        icon: const Icon(Icons.add_rounded),
                                        label: Text(t('create_first_group_label'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.cyan,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                                          elevation: 0,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Search bar + filters menu at the top
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: AppSearchBar(
                                        controller: _groupSearchCtrl,
                                        hintText: t('search_group_name_or_creator_email_hint'),
                                        onChanged: (val) {
                                          groupSearchQuery = val;
                                          _filterAndSearchGroups();
                                        },
                                        margin: EdgeInsets.zero,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(
                                          colors: [
                                            Colors.orange,
                                            Colors.white,
                                            Colors.green
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(2),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: AppThemeColors.cardBg(context),
                                          shape: BoxShape.circle,
                                        ),
                                        child: IconButton(
                                          icon: Icon(Icons.more_vert,
                                              color: AppColors.cyan),
                                          tooltip: t('filters_label'),
                                          onPressed: _showCreateGroupFiltersSheet,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 20),
                                BudgetLimitBanner(
                                  type: 'group',
                                  refreshTrigger: _bannerRefreshTrigger,
                                  onTap: () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => const BudgetPlanningPage())),
                                  onViewMessages: () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => const BudgetMessagesPage())),
                                ),
                                const SizedBox(height: 6),
                                const FreeAttemptsBanner(featureKey: 'group_creation'),
                                const SizedBox(height: 8),
                                // Filter chips
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(children: [
                                    for (final f in [
                                      ('all', t('filter_all')),
                                      ('created', t('filter_created_by_me')),
                                      ('member', t('filter_joined')),
                                    ]) ...[
                                      GestureDetector(
                                        onTap: () { setState(() => groupFilter = f.$1); _filterAndSearchGroups(); },
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 180),
                                          margin: const EdgeInsets.only(right: 8),
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                          decoration: BoxDecoration(
                                            color: groupFilter == f.$1 ? AppColors.cyan : AppThemeColors.cardBg(context),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: groupFilter == f.$1 ? AppColors.cyan : AppThemeColors.border(context)),
                                          ),
                                          child: Text(f.$2, style: TextStyle(
                                            fontSize: 12, fontWeight: FontWeight.w600,
                                            color: groupFilter == f.$1 ? Colors.white : AppThemeColors.primaryText(context),
                                          )),
                                        ),
                                      ),
                                    ],
                                  ]),
                                ),
                                const SizedBox(height: 8),
                                // Member filter strip
                                Builder(builder: (ctx) {
                                  final session = Provider.of<SessionProvider>(ctx, listen: false);
                                  final myEmail = session.user?['email']?.toString() ?? '';
                                  final seen = <String>{};
                                  final members = <Map<String, dynamic>>[{'email': 'all', 'name': 'All'}];
                                  for (final g in userGroups) {
                                    for (final m in (g['members'] as List? ?? [])) {
                                      if (m is Map) {
                                        final email = (m['email'] ?? '').toString();
                                        final name = (m['name'] ?? m['username'] ?? email.split('@').first).toString();
                                        if (email.isNotEmpty && email != myEmail && !seen.contains(email)) {
                                          seen.add(email);
                                          final pic = (m['profileImage'] ?? m['profilePicture'] ?? '').toString();
                                          members.add({'email': email, 'name': name, 'profileImage': pic});
                                        }
                                      }
                                    }
                                  }
                                  if (members.length <= 1) return const SizedBox.shrink();
                                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(children: [
                                        Container(width: 20, height: 20, decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)),
                                          child: const Icon(Icons.people_alt_outlined, size: 12, color: AppColors.cyan)),
                                        const SizedBox(width: 6),
                                        Text('Filter by Member', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppThemeColors.secondaryText(ctx))),
                                      ]),
                                    ),
                                    SizedBox(
                                      height: 60,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: members.length,
                                        itemBuilder: (ctx2, mi) {
                                          final m = members[mi];
                                          final email = m['email'] as String;
                                          final name = m['name'] as String;
                                          final pic = (m['profileImage'] ?? '').toString();
                                          final isAll = email == 'all';
                                          final isSelected = _memberEmailFilter == email;
                                          return GestureDetector(
                                            onTap: () {
                                              setState(() => _memberEmailFilter = isSelected && !isAll ? 'all' : email);
                                              _filterAndSearchGroups();
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.only(right: 10),
                                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                                Container(
                                                  width: 36, height: 36,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(color: isSelected ? AppColors.cyan : AppThemeColors.border(ctx2), width: isSelected ? 2 : 1),
                                                  ),
                                                  child: ClipOval(
                                                    child: (!isAll && pic.isNotEmpty)
                                                      ? Image.network(pic, width: 36, height: 36, fit: BoxFit.cover,
                                                          errorBuilder: (_, __, ___) => Container(
                                                            color: isSelected ? AppColors.cyan.withValues(alpha: 0.14) : AppThemeColors.surfaceBg(ctx2),
                                                            child: Icon(Icons.person_rounded, size: 17, color: isSelected ? AppColors.cyan : AppThemeColors.secondaryText(ctx2)),
                                                          ))
                                                      : Container(
                                                          color: isSelected ? AppColors.cyan.withValues(alpha: 0.14) : AppThemeColors.surfaceBg(ctx2),
                                                          child: Icon(isAll ? Icons.groups_rounded : Icons.person_rounded, size: 17,
                                                            color: isSelected ? AppColors.cyan : AppThemeColors.secondaryText(ctx2)),
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                SizedBox(
                                                  width: 46,
                                                  child: Text(
                                                    isAll ? 'All' : name.split(' ').first,
                                                    maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                                    style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                                      color: isSelected ? AppColors.cyan : AppThemeColors.secondaryText(ctx2)),
                                                  ),
                                                ),
                                              ]),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ]);
                                }),
                                if (_showFavouritesOnly &&
                                    filteredGroups.isEmpty)
                                  Container(
                                    padding:
                                        const EdgeInsets.all(3), // border width
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Colors.orange,
                                          Colors.white,
                                          Colors.green
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(21),
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: AppThemeColors.cardBg(context),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(32.0),
                                        child: Column(
                                          children: [
                                            Icon(Icons.star_border,
                                                color: Colors.grey, size: 60),
                                            SizedBox(height: 16),
                                            Text(
                                              t('no_favourite_groups_yet_message'),
                                              style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.cyan,
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              t('mark_groups_as_favourites_message'),
                                              style: TextStyle(
                                                  fontSize: 16,
                                                  color: AppThemeColors.secondaryText(context)),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  ...filteredGroups.map((g) {
                                    final groupColor = g['color'] != null
                                        ? Color(int.parse(g['color']
                                            .toString()
                                            .replaceFirst('#', '0xff')))
                                        : Colors.blue.shade300;
                                    final gId = g['_id']?.toString() ?? '';
                                    final gBudget = _groupBudgetSpending[gId];
                                    final gHasLimit = gBudget != null && gBudget['budget'] != null;
                                    final gSpent = (gBudget?['spent'] as num? ?? 0).toDouble();
                                    final gLimit = gHasLimit ? (gBudget['budget'] as num).toDouble() : 0.0;
                                    final gPct = gHasLimit && gLimit > 0 ? (gSpent / gLimit).clamp(0.0, 1.0) : 0.0;
                                    final gLimitExceeded = gHasLimit && gSpent > gLimit;
                                    final gColor = gLimitExceeded ? Colors.red.shade600 : gPct >= 0.85 ? Colors.orange.shade700 : Colors.teal;
                                    return Container(
                                      height: 185,
                                      margin: const EdgeInsets.only(bottom: 18),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [BoxShadow(color: groupColor.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: Stack(fit: StackFit.expand, children: [
                                          Builder(builder: (_) {
                                            final imgUrl = (g['groupImageUrl']?.toString() ?? '').isNotEmpty
                                                ? g['groupImageUrl'].toString()
                                                : defaultGroupImageUrl(g['title']?.toString() ?? '');
                                            final gtitle = g['title']?.toString() ?? '';
                                            if (imgUrl.isEmpty) {
                                              return _gtImgPlaceholder(groupColor, gtitle);
                                            }
                                            return Image.network(imgUrl, fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => _gtImgPlaceholder(groupColor, gtitle));
                                          }),
                                          Container(
                                            decoration: const BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [Color(0x33000000), Color(0xDD000000)],
                                                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                              ),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () => _showGroupDetails(g),
                                            child: Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(children: [
                                                    Container(
                                                      width: 12, height: 12,
                                                      decoration: BoxDecoration(color: groupColor, shape: BoxShape.circle,
                                                        border: Border.all(color: Colors.white, width: 1.5)),
                                                    ),
                                                    Builder(builder: (badgeCtx) {
                                                      final myEmail = (Provider.of<SessionProvider>(badgeCtx, listen: false).user?['email'] ?? '').toString().toLowerCase();
                                                      final creatorEmail = (g['creator']?['email'] ?? '').toString().toLowerCase();
                                                      if (myEmail.isEmpty || myEmail != creatorEmail) return const SizedBox.shrink();
                                                      return Container(
                                                        margin: const EdgeInsets.only(left: 6),
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: groupColor.withValues(alpha: 0.85),
                                                          borderRadius: BorderRadius.circular(20),
                                                        ),
                                                        child: Text(AppLocalizations.of(badgeCtx).t('creator_badge_label'),
                                                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                                                      );
                                                    }),
                                                    if (_budgetStatusLoading)
                                                      const Padding(
                                                        padding: EdgeInsets.only(left: 8),
                                                        child: SizedBox(width: 12, height: 12,
                                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
                                                      )
                                                    else if (gHasLimit)
                                                      GestureDetector(
                                                        onTap: gLimitExceeded
                                                            ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetMessagesPage()))
                                                            : null,
                                                        child: Container(
                                                          margin: const EdgeInsets.only(left: 8),
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                          decoration: BoxDecoration(color: gColor.withValues(alpha: 0.90), borderRadius: BorderRadius.circular(20)),
                                                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                            Icon(gLimitExceeded ? Icons.warning_amber_rounded : Icons.account_balance_wallet_outlined,
                                                              color: Colors.white, size: 11),
                                                            const SizedBox(width: 4),
                                                            Text(
                                                              gLimitExceeded ? 'Over budget' : '₹${gSpent.toStringAsFixed(0)}/₹${gLimit.toStringAsFixed(0)}',
                                                              style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
                                                            ),
                                                          ]),
                                                        ),
                                                      ),
                                                    const Spacer(),
                                                    Builder(builder: (starCtx) {
                                                      final myEmail = (Provider.of<SessionProvider>(starCtx, listen: false).user?['email'] ?? '').toString();
                                                      final isFav = (g['favourite'] as List? ?? []).contains(myEmail);
                                                      return GestureDetector(
                                                        onTap: () => _toggleFavourite(gId),
                                                        child: Container(
                                                          padding: const EdgeInsets.all(6),
                                                          decoration: const BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
                                                          child: Icon(
                                                            isFav ? Icons.star_rounded : Icons.star_border_rounded,
                                                            color: isFav ? Colors.amber : Colors.white70,
                                                            size: 16,
                                                          ),
                                                        ),
                                                      );
                                                    }),
                                                  ]),
                                                  const Spacer(),
                                                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                      Text(g['title']?.toString() ?? '',
                                                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold,
                                                          shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
                                                      const SizedBox(height: 5),
                                                      Row(children: [
                                                        // Stacked member avatars
                                                        ...((g['members'] as List).take(4).toList().asMap().entries.map((e) {
                                                          final mu = e.value is Map
                                                              ? ((e.value['user'] is Map) ? e.value['user'] as Map : e.value as Map)
                                                              : <String, dynamic>{};
                                                          final mp = (mu['profileImage'] ?? mu['profilePicture'] ?? '').toString();
                                                          final mi = (mu['name'] ?? mu['email'] ?? '?').toString();
                                                          final initial = mi.isNotEmpty ? mi[0].toUpperCase() : '?';
                                                          return Transform.translate(
                                                            offset: Offset(e.key * -5.0, 0),
                                                            child: CircleAvatar(
                                                              radius: 10,
                                                              backgroundColor: AppColors.cyan,
                                                              child: ClipOval(
                                                                child: mp.isNotEmpty
                                                                    ? Image.network(mp,
                                                                        width: 20, height: 20,
                                                                        fit: BoxFit.cover,
                                                                        errorBuilder: (_, __, ___) => Center(
                                                                          child: Text(initial,
                                                                              style: const TextStyle(fontSize: 8, color: Colors.white)),
                                                                        ))
                                                                    : Center(child: Text(initial,
                                                                        style: const TextStyle(fontSize: 8, color: Colors.white))),
                                                              ),
                                                            ),
                                                          );
                                                        })),
                                                        SizedBox(width: (g['members'] as List).length > 4 ? 2.0 : 6.0),
                                                        Text(
                                                          (g['members'] as List).length > 4
                                                              ? '+${(g['members'] as List).length - 4}'
                                                              : '${(g['members'] as List).length} member${(g['members'] as List).length == 1 ? '' : 's'}',
                                                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                                                        ),
                                                      ]),
                                                      Builder(builder: (pbCtx) {
                                                        final pending = (g['userPendingBalance'] as num? ?? 0).toDouble();
                                                        if (pending == 0) return const SizedBox.shrink();
                                                        final tl = AppLocalizations.of(pbCtx).t;
                                                        return Padding(
                                                          padding: const EdgeInsets.only(top: 4),
                                                          child: Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                            decoration: BoxDecoration(
                                                              color: pending > 0 ? Colors.red.withValues(alpha: 0.8) : Colors.green.withValues(alpha: 0.8),
                                                              borderRadius: BorderRadius.circular(20),
                                                            ),
                                                            child: Text(
                                                              '₹${pending.abs().toStringAsFixed(0)} ${pending > 0 ? tl('pending_owed_label') : tl('pending_to_receive_label')}',
                                                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                            ),
                                                          ),
                                                        );
                                                      }),
                                                    ])),
                                                    Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                                      Stack(
                                                        clipBehavior: Clip.none,
                                                        children: [
                                                          GestureDetector(
                                                            onTap: () => Navigator.push(context, MaterialPageRoute(
                                                              builder: (_) => GroupChatPage(
                                                                groupTransactionId: gId,
                                                                groupTitle: g['title']?.toString() ?? '',
                                                                members: (g['members'] as List? ?? []),
                                                                groupImageUrl: g['groupImageUrl']?.toString(),
                                                              ),
                                                            )),
                                                            child: Container(
                                                              margin: const EdgeInsets.only(bottom: 6),
                                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                                                              child: Builder(builder: (btnCtx) => Row(mainAxisSize: MainAxisSize.min, children: [
                                                                const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 13),
                                                                const SizedBox(width: 4),
                                                                Text(AppLocalizations.of(btnCtx).t('chat_label'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                                              ])),
                                                            ),
                                                          ),
                                                          if ((g['unreadMessageCount'] as num? ?? 0) > 0)
                                                            Positioned(
                                                              right: -2, top: -2,
                                                              child: Container(
                                                                width: 9, height: 9,
                                                                decoration: BoxDecoration(
                                                                  color: Colors.green.shade500,
                                                                  shape: BoxShape.circle,
                                                                  border: Border.all(color: Colors.white, width: 1.5),
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                      Builder(builder: (bCtx) {
                                                        final myEmail = (Provider.of<SessionProvider>(bCtx, listen: false).user?['email'] ?? '').toString().toLowerCase();
                                                        final creatorEmail = (g['creator']?['email'] ?? '').toString().toLowerCase();
                                                        final isCardCreator = myEmail.isNotEmpty && myEmail == creatorEmail;
                                                        final isUploading = _uploadingImageGroupId == gId;
                                                        if (!isCardCreator) return const SizedBox.shrink();
                                                        return GestureDetector(
                                                          onTap: () => _pickGroupImageFromCard(g),
                                                          child: Container(
                                                            margin: const EdgeInsets.only(bottom: 8),
                                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                                                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                              isUploading
                                                                  ? const SizedBox(width: 12, height: 12,
                                                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                                                  : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 13),
                                                              const SizedBox(width: 4),
                                                              const Text('Change photo',
                                                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                                            ]),
                                                          ),
                                                        );
                                                      }),
                                                      OutlinedButton(
                                                        onPressed: () => _showGroupDetails(g),
                                                        style: OutlinedButton.styleFrom(
                                                          foregroundColor: Colors.white,
                                                          side: const BorderSide(color: Colors.white, width: 1.5),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                                                          minimumSize: Size.zero,
                                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                        ),
                                                        child: Text('${t('view_details_label')} →',
                                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                                                      ),
                                                    ]),
                                                  ]),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ]),
                                      ),
                                    );
                                  }),
                              ],
                            ),
            ),
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Colors.orange, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: FloatingActionButton(
          onPressed: _showCreateGroup,
          backgroundColor: Colors.transparent,
          elevation: 0,
          tooltip: t('create_new_group_label'),
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
    );
  }







  // Member Selection Dialog

  // Helper function to format date and time

}
