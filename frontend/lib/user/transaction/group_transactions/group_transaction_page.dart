import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import 'group_detail_page.dart';
import 'create_group_page.dart';
import '../../../widgets/stylish_dialog.dart';

String _emailOf(dynamic field) {
  if (field == null) return '-';
  if (field is Map) return (field['email'] ?? '-').toString();
  return field.toString();
}

class GroupTransactionPage extends StatefulWidget {
  final List<String>? prefillMemberEmails;

  const GroupTransactionPage({Key? key, this.prefillMemberEmails})
      : super(key: key);
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
  int? _dailyGroupRemaining;

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

  @override
  void initState() {
    super.initState();
    if (widget.prefillMemberEmails != null &&
        widget.prefillMemberEmails!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showCreateGroup(prefill: widget.prefillMemberEmails);
      });
    }
    _loadSupportedCurrencies();
    _fetchUserGroups();
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


  Widget _buildErrorState(String message, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red[300]!, Colors.orange[400]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(21),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
                      child: Icon(Icons.wifi_off_rounded, size: 48, color: Colors.red[400]),
                    ),
                    const SizedBox(height: 16),
                    Text('Oops! Something went wrong',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red[700]),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
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
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
        setState(() {
          error =
              'Failed to load groups. Please try again.';
          groupsLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Unable to connect. Please check your internet connection.';
        groupsLoading = false;
      });
    }
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
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
              Text('Joined: ${member['joinedAt'].toString().substring(0, 10)}',
                  style: TextStyle(fontSize: 14, color: Colors.grey)),
            if (member['leftAt'] != null)
              Text('Left: ${member['leftAt'].toString().substring(0, 10)}',
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
    ).then((_) => _fetchUserGroups());
  }

  Future<void> _showCreateGroup({List<String>? prefill}) async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.isSubscribed) {
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
            message:
                'You\'ve reached today\'s limit of 1 group creation. Free attempts are also paused until tomorrow.\n\nSubscribe for unlimited access.');
        return;
      }
      final freeRemaining = session.freeGroupsRemaining ?? 0;
      if (freeRemaining <= 0) {
        final coins = session.lenDenCoins ?? 0;
        final useCoins = await showFreeAttemptsExhaustedDialog(context,
            featureName: 'group creation', coinCost: 20, currentCoins: coins);
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
                height: 100,
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
            top: 40,
            left: 16,
            right: 16,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                group == null
                    ? 'Group Transactions'
                    : 'Group: ${group?['title'] ?? ''}',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  shadows: [Shadow(color: Colors.black26, blurRadius: 4)],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
                top:
                    180), // Add top padding to move content below the wavy header
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: groupsLoading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null && userGroups.isEmpty
                      ? _buildErrorState(error!, _fetchUserGroups)
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
                                      'No Groups Yet!',
                                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.cyan),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Split expenses with friends & family effortlessly.\nTap "+" to create your first group!',
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
                                        label: const Text('Create First Group', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
                                // Search bar at the top
                                Container(
                                  padding:
                                      const EdgeInsets.all(2), // border width
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
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: TextField(
                                    decoration: InputDecoration(
                                      hintText:
                                          'Search by group name or creator email...',
                                      prefixIcon: Icon(Icons.search,
                                          color: AppColors.cyan),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: EdgeInsets.symmetric(
                                          vertical: 0, horizontal: 16),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    onChanged: (val) {
                                      groupSearchQuery = val;
                                      _filterAndSearchGroups();
                                    },
                                  ),
                                ),
                                SizedBox(height: 16),

                                // Filters in a scrollable row below search bar
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      Container(
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
                                        padding: const EdgeInsets.all(2),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          child: IconButton(
                                            icon: Icon(
                                              _showFavouritesOnly
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              color: _showFavouritesOnly
                                                  ? Colors.amber
                                                  : AppColors.cyan,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _showFavouritesOnly =
                                                    !_showFavouritesOnly;
                                              });
                                              _filterAndSearchGroups();
                                            },
                                            tooltip: 'Show Favourites Only',
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Container(
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
                                        padding: const EdgeInsets.all(2),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          child: DropdownButton<String>(
                                            value: groupFilter,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            style: const TextStyle(
                                                color: AppColors.cyan,
                                                fontWeight: FontWeight.bold),
                                            underline: Container(),
                                            items: const [
                                              DropdownMenuItem(
                                                  value: 'all',
                                                  child: Text('All')),
                                              DropdownMenuItem(
                                                  value: 'created',
                                                  child: Text('Created by Me')),
                                              DropdownMenuItem(
                                                  value: 'member',
                                                  child: Text('Member')),
                                            ],
                                            onChanged: (val) {
                                              if (val != null) {
                                                setState(() {
                                                  groupFilter = val;
                                                });
                                                _filterAndSearchGroups();
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Container(
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
                                        padding: const EdgeInsets.all(2),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          child: DropdownButton<String>(
                                            value: groupSort,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            style: const TextStyle(
                                                color: AppColors.cyan,
                                                fontWeight: FontWeight.bold),
                                            underline: Container(),
                                            items: const [
                                              DropdownMenuItem(
                                                  value: 'newest',
                                                  child: Text('Newest')),
                                              DropdownMenuItem(
                                                  value: 'oldest',
                                                  child: Text('Oldest')),
                                              DropdownMenuItem(
                                                  value: 'name_az',
                                                  child: Text('Name A-Z')),
                                              DropdownMenuItem(
                                                  value: 'name_za',
                                                  child: Text('Name Z-A')),
                                              DropdownMenuItem(
                                                  value: 'members_high',
                                                  child:
                                                      Text('Members High-Low')),
                                              DropdownMenuItem(
                                                  value: 'members_low',
                                                  child:
                                                      Text('Members Low-High')),
                                            ],
                                            onChanged: (val) {
                                              if (val != null) {
                                                setState(() {
                                                  groupSort = val;
                                                });
                                                _filterAndSearchGroups();
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Container(
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
                                        padding: const EdgeInsets.all(2),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          child: DropdownButton<String>(
                                            value: memberCountFilter,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            style: const TextStyle(
                                                color: AppColors.cyan,
                                                fontWeight: FontWeight.bold),
                                            underline: Container(),
                                            items: const [
                                              DropdownMenuItem(
                                                  value: 'all',
                                                  child: Text('All Members')),
                                              DropdownMenuItem(
                                                  value: '2-5',
                                                  child: Text('2-5')),
                                              DropdownMenuItem(
                                                  value: '6-10',
                                                  child: Text('6-10')),
                                              DropdownMenuItem(
                                                  value: '10+',
                                                  child: Text('10+'))
                                            ],
                                            onChanged: (val) {
                                              if (val != null) {
                                                setState(() {
                                                  memberCountFilter = val;
                                                });
                                                _filterAndSearchGroups();
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Container(
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
                                        padding: const EdgeInsets.all(2),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          child: DropdownButton<String>(
                                            value: dateFilter,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            style: const TextStyle(
                                                color: AppColors.cyan,
                                                fontWeight: FontWeight.bold),
                                            underline: Container(),
                                            items: const [
                                              DropdownMenuItem(
                                                  value: 'all',
                                                  child: Text('All Dates')),
                                              DropdownMenuItem(
                                                  value: '7days',
                                                  child: Text('Last 7 Days')),
                                              DropdownMenuItem(
                                                  value: '30days',
                                                  child: Text('Last 30 Days')),
                                              DropdownMenuItem(
                                                  value: 'custom',
                                                  child: Text('Custom'))
                                            ],
                                            onChanged: (val) async {
                                              if (val != null) {
                                                setState(() {
                                                  dateFilter = val;
                                                });
                                                if (val == 'custom') {
                                                  final picked =
                                                      await showDateRangePicker(
                                                    context: context,
                                                    firstDate: DateTime(2020),
                                                    lastDate: DateTime.now(),
                                                  );
                                                  if (picked != null) {
                                                    setState(() {
                                                      customStartDate =
                                                          picked.start;
                                                      customEndDate =
                                                          picked.end;
                                                    });
                                                  }
                                                }
                                                _filterAndSearchGroups();
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 16),
                                Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(
                                          3), // border width
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
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16, horizontal: 20),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(18),
                                        ),
                                        child: Consumer<SessionProvider>(
                                          builder: (context, session, child) {
                                            final bool dailyLimitReached =
                                                !session.isSubscribed &&
                                                    _dailyGroupRemaining !=
                                                        null &&
                                                    _dailyGroupRemaining! <= 0;
                                            // null = still loading → optimistically enabled
                                            final freeRemaining =
                                                session.freeGroupsRemaining;
                                            final bool canCreate = session
                                                    .isSubscribed ||
                                                (!dailyLimitReached &&
                                                    (freeRemaining == null ||
                                                        freeRemaining > 0)) ||
                                                (session.lenDenCoins ?? 0) >=
                                                    20;
                                            return Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                if (!session.isSubscribed &&
                                                    (session.freeGroupsRemaining ??
                                                            0) >
                                                        0)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            bottom: 8.0),
                                                    child: Text(
                                                      '${session.freeGroupsRemaining} free group creations remaining.',
                                                      style: TextStyle(
                                                          color: Colors.green),
                                                    ),
                                                  ),
                                                ElevatedButton.icon(
                                                  onPressed: canCreate
                                                      ? _showCreateGroup
                                                      : null,
                                                  icon:
                                                      Icon(Icons.add, size: 28),
                                                  label: Text(
                                                      'Create New Group',
                                                      style: TextStyle(
                                                          fontSize: 18)),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor: canCreate
                                                        ? AppColors.cyan
                                                        : Colors.grey,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 24,
                                                            vertical: 12),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        12)),
                                                    elevation: 4,
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                SizedBox(height: 20),
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
                                        color: Colors.white,
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
                                              'No Favourite Groups Yet!',
                                              style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.cyan,
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              'Mark groups as favourites to see them here.',
                                              style: TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.grey[700]),
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
                                    return Card(
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(18)),
                                      elevation: 6,
                                      margin: EdgeInsets.only(bottom: 18),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: groupColor,
                                            width: 2,
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
                                                              'View Details',
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
                                                        CircleAvatar(
                                                          backgroundColor:
                                                              groupColor,
                                                          radius: 22,
                                                          child: Text(
                                                              avatarText,
                                                              style: TextStyle(
                                                                  fontSize: 22,
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold)),
                                                        ),
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
                                                          Icon(Icons.person, size: 18, color: Colors.grey),
                                                          SizedBox(width: 4),
                                                          Text(
                                                            'Creator: ${_emailOf(g['creator'])}',
                                                            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
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
                                                            'Members: ${(g['members'] as List).length}',
                                                            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                                                          ),
                                                          SizedBox(width: 10),
                                                          ...((g['members'] as List).map((m) => GestureDetector(
                                                            onTap: () => _showMemberDetails(m),
                                                            child: Padding(
                                                              padding: const EdgeInsets.symmetric(horizontal: 2),
                                                              child: CircleAvatar(
                                                                radius: 13,
                                                                backgroundColor: Colors
                                                                    .primaries[
                                                                      (_emailOf(m).hashCode.abs()) %
                                                                          Colors.primaries.length
                                                                    ].shade200,
                                                                child: Text(
                                                                  _emailOf(m).isNotEmpty && _emailOf(m) != '-'
                                                                      ? _emailOf(m)[0].toUpperCase()
                                                                      : '?',
                                                                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                                                ),
                                                              ),
                                                            ),
                                                          ))),
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
                                                            'Created: ${g['createdAt'] != null ? g['createdAt'].toString().substring(0, 10) : ''}',
                                                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
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
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/user/dashboard'),
              ),
            ),
          ),
        ],
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
