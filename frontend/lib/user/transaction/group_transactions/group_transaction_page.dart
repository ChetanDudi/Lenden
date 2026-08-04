import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import 'group_detail_page.dart';
import 'create_group_page.dart';
import '../../../widgets/stylish_dialog.dart';
import '../../../widgets/app_widgets.dart';
import '../../../api_config.dart';
import '../../../utils/responsive.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/budget_limit_banner.dart';
import '../../../widgets/free_attempts_banner.dart';
import '../../budget/budget_messages_page.dart';
import '../../budget/budget_planning_page.dart';
import 'package:image_picker/image_picker.dart';

String _emailOf(dynamic field) {
  if (field == null) return '-';
  if (field is Map) return (field['email'] ?? '-').toString();
  return field.toString();
}

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

  // Expense state
  final TextEditingController _expenseDescController = TextEditingController();
  final TextEditingController _expenseAmountController =
      TextEditingController();
  String _expenseCurrency = 'INR';
  String splitType = 'equal';
  List<Map<String, dynamic>> customSplits = [];
  List<String> selectedMembers = []; // New: selected members for expense
  Map<String, double> customSplitAmounts =
      {}; // New: track custom split amounts for each member
  bool addingExpense = false;
  String? expenseError;
  List<Map<String, String>> _currencies = [
    {'code': 'INR', 'symbol': '₹'},
    {'code': 'USD', 'symbol': '\$'},
    {'code': 'EUR', 'symbol': '€'},
    {'code': 'GBP', 'symbol': '£'},
    {'code': 'JPY', 'symbol': '¥'},
    {'code': 'CNY', 'symbol': '¥'},
    {'code': 'CAD', 'symbol': '\$'},
    {'code': 'AUD', 'symbol': '\$'},
    {'code': 'CHF', 'symbol': 'Fr'},
    {'code': 'RUB', 'symbol': '₽'},
  ];

  List<Map<String, dynamic>> userGroups = [];
  List<Map<String, dynamic>> filteredGroups = [];
  bool groupsLoading = true;
  String groupSearchQuery = '';
  String groupFilter = 'all'; // all, created, member
  String groupSort =
      'newest'; // newest, oldest, name_az, name_za, members_high, members_low
  String memberCountFilter = 'all'; // all, 2-5, 6-10, 10+
  String dateFilter = 'all'; // all, 7days, 30days, custom
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
    _loadSupportedCurrencies();
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
    _expenseDescController.dispose();
    _expenseAmountController.dispose();
    super.dispose();
  }




  // Initialize selected members for expense (start with no members selected)

  // Initialize custom split amounts for selected members

  // Get total amount entered for custom split

  // Get remaining amount for custom split

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

  Future<void> _loadSupportedCurrencies() async {
    try {
      final res = await ApiClient.get('/api/currency-conversions/supported');
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      final currencies =
          List<Map<String, dynamic>>.from(data['currencies'] ?? const []);
      if (currencies.isEmpty) return;
      setState(() {
        _currencies = currencies
            .map(
              (item) => {
                'code': (item['code'] ?? 'INR').toString().toUpperCase(),
                'symbol': (item['symbol'] ?? item['code'] ?? '₹').toString(),
              },
            )
            .toList();
        if (!_currencies.any((item) => item['code'] == _expenseCurrency)) {
          _expenseCurrency = 'INR';
        }
      });
    } catch (_) {}
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
        setState(() {
          userGroups = loaded;
          groupsLoading = false;
        });
        _filterAndSearchGroups();
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

  void _showMemberDetails(Map<String, dynamic> member) {
    final t = AppLocalizations.of(context).t;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppThemeColors.cardBg(context),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: Colors
                  .primaries[(member['email'] ?? '').toString().hashCode %
                      Colors.primaries.length]
                  .shade300,
              radius: 32,
              child: Text(
                () {
                  final email = (member['email'] ?? '').toString();
                  return email.isNotEmpty ? email[0].toUpperCase() : '?';
                }(),
                style: TextStyle(
                    fontSize: 32,
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: 16),
            Text((member['email'] ?? '').toString(),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (member['joinedAt'] != null)
              Text(t('joined_date_label').replaceFirst('{date}', member['joinedAt'].toString().substring(0, 10)),
                  style: TextStyle(fontSize: 14, color: Colors.grey)),
            if (member['leftAt'] != null)
              Text(t('left_date_label').replaceFirst('{date}', member['leftAt'].toString().substring(0, 10)),
                  style: TextStyle(fontSize: 14, color: Colors.red)),
          ],
        ),
      ),
    );
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

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingImageGroupId = gId);
    try {
      final bytes = await picked.readAsBytes();
      final res = await ApiClient.putMultipart(
        '/api/group-transactions/$gId/image',
        files: [ApiMultipartFile(field: 'groupImage', filename: picked.name, bytes: bytes)],
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
              gradient: const LinearGradient(
                colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
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
              clipper: TopWaveClipper(),
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
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFFFF9933), Color(0xFFFFFFFF), Color(0xFF138808)],
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
                                      child: Container(
                                        padding: const EdgeInsets.all(
                                            2), // border width
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
                                          borderRadius:
                                              BorderRadius.circular(18),
                                        ),
                                        child: TextField(
                                          decoration: InputDecoration(
                                            hintText:
                                                t('search_group_name_or_creator_email_hint'),
                                            prefixIcon: Icon(Icons.search,
                                                color: AppColors.cyan),
                                            filled: true,
                                            fillColor: AppThemeColors.cardBg(context),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    vertical: 0,
                                                    horizontal: 16),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              borderSide: BorderSide.none,
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              borderSide: BorderSide.none,
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              borderSide: BorderSide.none,
                                            ),
                                          ),
                                          onChanged: (val) {
                                            groupSearchQuery = val;
                                            _filterAndSearchGroups();
                                          },
                                        ),
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
                                const SizedBox(height: 4),
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
                                    final avatarText = () {
                                      final title = g['title'] ?? '';
                                      return title.isNotEmpty
                                          ? title[0].toUpperCase()
                                          : '?';
                                    }();
                                    final gId = g['_id']?.toString() ?? '';
                                    final gBudget = _groupBudgetSpending[gId];
                                    final gHasLimit = gBudget != null && gBudget['budget'] != null;
                                    final gSpent = (gBudget?['spent'] as num? ?? 0).toDouble();
                                    final gLimit = gHasLimit ? (gBudget['budget'] as num).toDouble() : 0.0;
                                    final gPct = gHasLimit && gLimit > 0 ? (gSpent / gLimit).clamp(0.0, 1.0) : 0.0;
                                    final gLimitExceeded = gHasLimit && gSpent > gLimit;
                                    final gColor = gLimitExceeded ? Colors.red.shade600 : gPct >= 0.85 ? Colors.orange.shade700 : Colors.teal;
                                    return Card(
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(18)),
                                      elevation: 6,
                                      margin: EdgeInsets.only(bottom: 18),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: gHasLimit ? gColor.withValues(alpha: 0.6) : groupColor,
                                            width: gLimitExceeded ? 2.5 : 2,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(18),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 18, horizontal: 18),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    if (_budgetStatusLoading) ...[
                                                      Container(
                                                        margin: const EdgeInsets.only(bottom: 10),
                                                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                                        decoration: BoxDecoration(
                                                          color: AppThemeColors.border(context).withValues(alpha: 0.4),
                                                          borderRadius: BorderRadius.circular(10),
                                                          border: Border.all(color: AppThemeColors.border(context)),
                                                        ),
                                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                          Row(children: [
                                                            Container(width: 14, height: 14,
                                                                decoration: BoxDecoration(color: AppThemeColors.secondaryText(context).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(3))),
                                                            const SizedBox(width: 6),
                                                            Container(width: 120, height: 11,
                                                                decoration: BoxDecoration(color: AppThemeColors.secondaryText(context).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(3))),
                                                          ]),
                                                          const SizedBox(height: 6),
                                                          ClipRRect(
                                                            borderRadius: BorderRadius.circular(3),
                                                            child: LinearProgressIndicator(
                                                              value: null,
                                                              minHeight: 4,
                                                              backgroundColor: AppThemeColors.border(context),
                                                            ),
                                                          ),
                                                        ]),
                                                      ),
                                                    ] else if (gHasLimit) ...[
                                                      GestureDetector(
                                                        onTap: gLimitExceeded ? () => Navigator.push(context,
                                                            MaterialPageRoute(builder: (_) => const BudgetMessagesPage())) : null,
                                                        child: Container(
                                                          margin: const EdgeInsets.only(bottom: 10),
                                                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                                                          decoration: BoxDecoration(
                                                            color: gColor.withValues(alpha: 0.07),
                                                            borderRadius: BorderRadius.circular(10),
                                                            border: Border.all(color: gColor.withValues(alpha: 0.3)),
                                                          ),
                                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                            Row(children: [
                                                              Icon(
                                                                gLimitExceeded ? Icons.warning_amber_rounded : Icons.account_balance_wallet_outlined,
                                                                color: gColor, size: 14,
                                                              ),
                                                              const SizedBox(width: 6),
                                                              Expanded(child: Text(
                                                                gLimitExceeded
                                                                    ? 'Budget exceeded · ₹${gSpent.toStringAsFixed(0)} / ₹${gLimit.toStringAsFixed(0)}'
                                                                    : 'Budget · ₹${gSpent.toStringAsFixed(0)} spent of ₹${gLimit.toStringAsFixed(0)}',
                                                                style: TextStyle(fontSize: context.sp(11), color: gColor, fontWeight: FontWeight.w600),
                                                              )),
                                                              if (gLimitExceeded)
                                                                Icon(Icons.chevron_right_rounded, size: 14, color: gColor),
                                                            ]),
                                                            const SizedBox(height: 5),
                                                            ClipRRect(
                                                              borderRadius: BorderRadius.circular(3),
                                                              child: LinearProgressIndicator(
                                                                value: gPct,
                                                                minHeight: 4,
                                                                backgroundColor: gColor.withValues(alpha: 0.15),
                                                                valueColor: AlwaysStoppedAnimation<Color>(gColor),
                                                              ),
                                                            ),
                                                          ]),
                                                        ),
                                                      ),
                                                    ],
                                                    // New row for Favourites and View Details buttons
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment.end,
                                                      children: [
                                                        ElevatedButton(
                                                          onPressed: () =>
                                                              _showGroupDetails(
                                                                  g),
                                                          style: ElevatedButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                Color(
                                                                    0xFF48CAE4),
                                                            shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            12)),
                                                            elevation: 0,
                                                          ),
                                                          child: Text(
                                                              t('view_details_label'),
                                                              style: TextStyle(
                                                                  color: Colors
                                                                      .white)),
                                                        ),
                                                      ],
                                                    ),
                                                    SizedBox(height: 10),
                                                    // Existing row with avatar, title, and color indicator
                                                    Row(
                                                      children: [
                                                        Builder(builder: (ctx) {
                                                          final myEmail = (Provider.of<SessionProvider>(ctx, listen: false).user?['email'] ?? '').toString().toLowerCase();
                                                          final creatorEmail = (g['creator']?['email'] ?? '').toString().toLowerCase();
                                                          final isCardCreator = myEmail.isNotEmpty && myEmail == creatorEmail;
                                                          final isUploading = _uploadingImageGroupId == gId;
                                                          return GestureDetector(
                                                            onTap: isCardCreator ? () => _pickGroupImageFromCard(g) : null,
                                                            child: Stack(
                                                              children: [
                                                                CircleAvatar(
                                                                  backgroundColor: groupColor,
                                                                  radius: 22,
                                                                  child: isUploading
                                                                      ? const SizedBox(width: 18, height: 18,
                                                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                                                      : ClipOval(
                                                                          child: (g['groupImageUrl'] != null &&
                                                                                  g['groupImageUrl'].toString().isNotEmpty)
                                                                              ? Image.network(
                                                                                  g['groupImageUrl'].toString(),
                                                                                  width: 44, height: 44, fit: BoxFit.cover,
                                                                                  errorBuilder: (_, __, ___) => Text(avatarText,
                                                                                      style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
                                                                                )
                                                                              : Text(avatarText,
                                                                                  style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
                                                                        ),
                                                                ),
                                                                if (isCardCreator && !isUploading)
                                                                  Positioned(
                                                                    right: 0, bottom: 0,
                                                                    child: Container(
                                                                      width: 16, height: 16,
                                                                      decoration: BoxDecoration(
                                                                        color: AppColors.cyan,
                                                                        shape: BoxShape.circle,
                                                                        border: Border.all(color: Colors.white, width: 1.5),
                                                                      ),
                                                                      child: const Icon(Icons.camera_alt_rounded, size: 9, color: Colors.white),
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                          );
                                                        }),
                                                        SizedBox(width: 14),
                                                        Expanded(
                                                          child: Text(
                                                            g['title'] ?? '',
                                                            style: TextStyle(
                                                                fontSize: 20,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Color(
                                                                    0xFF00B4D8)),
                                                          ),
                                                        ),
                                                        // Group color indicator
                                                        Container(
                                                          width: 18,
                                                          height: 18,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: groupColor,
                                                            shape:
                                                                BoxShape.circle,
                                                            border: Border.all(
                                                                color: Colors
                                                                    .white,
                                                                width: 2),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    SizedBox(height: 10),
                                                    // Creator — horizontal scroll
                                                    SingleChildScrollView(
                                                      scrollDirection: Axis.horizontal,
                                                      child: Row(
                                                        children: [
                                                          ClipOval(
                                                            child: (g['creator'] is Map &&
                                                                    (g['creator']['_id'] ?? '')
                                                                        .toString()
                                                                        .isNotEmpty)
                                                                ? Image.network(
                                                                    '${ApiConfig.baseUrl}/api/users/${g['creator']['_id']}/profile-image',
                                                                    width: 18,
                                                                    height: 18,
                                                                    fit: BoxFit.cover,
                                                                    errorBuilder: (context,
                                                                            error, stackTrace) =>
                                                                        Icon(Icons.person,
                                                                            size: 18,
                                                                            color: Colors.grey),
                                                                  )
                                                                : Icon(Icons.person,
                                                                    size: 18, color: Colors.grey),
                                                          ),
                                                          SizedBox(width: 4),
                                                          Text(
                                                            t('creator_colon_label').replaceFirst('{email}', _emailOf(g['creator'])),
                                                            style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(context)),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    SizedBox(height: 6),
                                                    // Members count + all avatars — horizontal scroll
                                                    SingleChildScrollView(
                                                      scrollDirection: Axis.horizontal,
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.people, size: 18, color: Colors.grey),
                                                          SizedBox(width: 4),
                                                          Text(
                                                            t('members_colon_label').replaceFirst('{count}', '${(g['members'] as List).length}'),
                                                            style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(context)),
                                                          ),
                                                          SizedBox(width: 10),
                                                          ...((g['members'] as List).map((m) {
                                                            final memberId = m is Map ? (m['_id'] ?? '').toString() : '';
                                                            final memberEmail = _emailOf(m);
                                                            final fallbackLetter = memberEmail.isNotEmpty && memberEmail != '-'
                                                                ? memberEmail[0].toUpperCase()
                                                                : '?';
                                                            final bgColor = Colors.primaries[
                                                                (memberEmail.hashCode.abs()) % Colors.primaries.length].shade200;
                                                            return GestureDetector(
                                                            onTap: () => _showMemberDetails(m),
                                                            child: Padding(
                                                              padding: const EdgeInsets.symmetric(horizontal: 2),
                                                              child: CircleAvatar(
                                                                radius: 13,
                                                                backgroundColor: bgColor,
                                                                child: ClipOval(
                                                                  child: memberId.isNotEmpty
                                                                      ? Image.network(
                                                                          '${ApiConfig.baseUrl}/api/users/$memberId/profile-image',
                                                                          width: 26,
                                                                          height: 26,
                                                                          fit: BoxFit.cover,
                                                                          errorBuilder: (context, error, stackTrace) => Text(
                                                                            fallbackLetter,
                                                                            style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                                                          ),
                                                                        )
                                                                      : Text(
                                                                          fallbackLetter,
                                                                          style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                                                        ),
                                                                ),
                                                              ),
                                                            ),
                                                          );
                                                          })),
                                                        ],
                                                      ),
                                                    ),
                                                    SizedBox(height: 6),
                                                    // Created at — horizontal scroll
                                                    SingleChildScrollView(
                                                      scrollDirection: Axis.horizontal,
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                                          SizedBox(width: 4),
                                                          Text(
                                                            t('created_colon_label').replaceFirst('{date}', g['createdAt'] != null ? g['createdAt'].toString().substring(0, 10) : ''),
                                                            style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context)),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ]),
                                        ),
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

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.8);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height,
      size.width * 0.5,
      size.height * 0.8,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.6,
      size.width,
      size.height * 0.8,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.moveTo(0, 0);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.6,
        size.width * 0.5, size.height * 0.4);
    path.quadraticBezierTo(size.width * 0.75, 0, size.width, size.height * 0.4);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class SettleWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.7);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height,
      size.width * 0.5,
      size.height * 0.7,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.4,
      size.width,
      size.height * 0.7,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
