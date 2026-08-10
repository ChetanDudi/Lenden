import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../widgets/app_colors.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/search_tab_bar.dart';

class AdminBudgetPage extends StatefulWidget {
  const AdminBudgetPage({super.key});

  @override
  State<AdminBudgetPage> createState() => _AdminBudgetPageState();
}

class _AdminBudgetPageState extends State<AdminBudgetPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  Map<String, dynamic>? _overview;
  bool _loadingOverview = false;
  String? _overviewErr;

  List<dynamic> _userRows = [];
  bool _loadingUsers = false;
  String? _usersErr;
  int _usersPage = 1;
  final _searchController = TextEditingController();

  List<dynamic> _subscriptions = [];
  bool _loadingSubs = false;
  String? _subsErr;

  // Override budget sheet state
  Map<String, dynamic>? _selectedUserBudget;
  bool _loadingUserBudget = false;

  // Set Override tab state
  final _overrideSearchCtrl = TextEditingController();

  // Collapsible state for personal budget cards
  final Set<String> _expandedPBIds = {};

  // Personal Budgets tab (tab 4)
  List<dynamic> _pbActive = [];
  bool _loadingPBActive = false;
  String? _pbActiveErr;
  int _pbActiveSkip = 0;
  bool _pbActiveHasMore = false;
  final _pbActiveSearch = TextEditingController();

  // Personal Budget History tab (tab 5)
  List<dynamic> _pbHistory = [];
  bool _loadingPBHistory = false;
  String? _pbHistoryErr;
  int _pbHistorySkip = 0;
  bool _pbHistoryHasMore = false;
  final _pbHistorySearch = TextEditingController();
  List<dynamic> _overrideResults = [];
  bool _overrideSearching = false;
  Map<String, dynamic>? _overrideUser;
  bool _overrideLoading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        switch (_tabs.index) {
          case 0: if (_overview == null) _fetchOverview(); break;
          case 1: if (_userRows.isEmpty) _fetchUsers(); break;
          case 3: if (_subscriptions.isEmpty) _fetchSubscriptions(); break;
          case 4: if (_pbActive.isEmpty) _fetchPBActive(reset: true); break;
          case 5: if (_pbHistory.isEmpty) _fetchPBHistory(reset: true); break;
        }
      }
    });
    _fetchOverview();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    _overrideSearchCtrl.dispose();
    _pbActiveSearch.dispose();
    _pbHistorySearch.dispose();
    super.dispose();
  }

  Future<void> _fetchPBActive({bool reset = false}) async {
    if (reset) { _pbActiveSkip = 0; _pbActive = []; }
    setState(() { _loadingPBActive = true; _pbActiveErr = null; });
    try {
      final q = _pbActiveSearch.text.trim();
      final url = '/api/admin/personal-budget/all-active?limit=10&skip=$_pbActiveSkip'
          '${q.isNotEmpty ? '&search=${Uri.encodeComponent(q)}' : ''}';
      final r = await ApiClient.get(url);
      if (!mounted) return;
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        final list = (d['budgets'] as List? ?? []);
        setState(() {
          if (reset) _pbActive = list; else _pbActive.addAll(list);
          _pbActiveSkip = _pbActive.length;
          _pbActiveHasMore = d['hasMore'] == true;
        });
      } else {
        setState(() => _pbActiveErr = 'Failed to load.');
      }
    } catch (e) {
      if (mounted) setState(() => _pbActiveErr = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loadingPBActive = false);
    }
  }

  Future<void> _fetchPBHistory({bool reset = false}) async {
    if (reset) { _pbHistorySkip = 0; _pbHistory = []; }
    setState(() { _loadingPBHistory = true; _pbHistoryErr = null; });
    try {
      final q = _pbHistorySearch.text.trim();
      final url = '/api/admin/personal-budget/all-history?limit=10&skip=$_pbHistorySkip'
          '${q.isNotEmpty ? '&search=${Uri.encodeComponent(q)}' : ''}';
      final r = await ApiClient.get(url);
      if (!mounted) return;
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        final list = (d['budgets'] as List? ?? []);
        setState(() {
          if (reset) _pbHistory = list; else _pbHistory.addAll(list);
          _pbHistorySkip = _pbHistory.length;
          _pbHistoryHasMore = d['hasMore'] == true;
        });
      } else {
        setState(() => _pbHistoryErr = 'Failed to load.');
      }
    } catch (e) {
      if (mounted) setState(() => _pbHistoryErr = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loadingPBHistory = false);
    }
  }

  Future<void> _fetchOverview() async {
    setState(() { _loadingOverview = true; _overviewErr = null; });
    try {
      final r = await ApiClient.get('/api/admin/budget/overview');
      if (r.statusCode == 200) setState(() { _overview = jsonDecode(r.body); });
      else setState(() { _overviewErr = 'Failed to load overview'; });
    } catch (e) { setState(() { _overviewErr = 'Error: $e'; }); }
    setState(() { _loadingOverview = false; });
  }

  Future<void> _fetchUsers({bool reset = false}) async {
    if (reset) { _usersPage = 1; _userRows = []; }
    setState(() { _loadingUsers = true; _usersErr = null; });
    try {
      final q = _searchController.text.trim();
      final url = '/api/admin/budget/users?page=$_usersPage&limit=20${q.isNotEmpty ? '&search=${Uri.encodeComponent(q)}' : ''}';
      final r = await ApiClient.get(url);
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        setState(() {
          _userRows = d['rows'] as List? ?? [];
        });
      } else setState(() { _usersErr = 'Failed to load users'; });
    } catch (e) { setState(() { _usersErr = 'Error: $e'; }); }
    setState(() { _loadingUsers = false; });
  }

  Future<void> _fetchSubscriptions() async {
    setState(() { _loadingSubs = true; _subsErr = null; });
    try {
      final r = await ApiClient.get('/api/admin/budget/subscriptions');
      if (r.statusCode == 200) setState(() { _subscriptions = jsonDecode(r.body)['subscriptions'] ?? []; });
      else setState(() { _subsErr = 'Failed to load subscriptions'; });
    } catch (e) { setState(() { _subsErr = 'Error: $e'; }); }
    setState(() { _loadingSubs = false; });
  }

  Future<void> _loadUserBudgetDetail(Map<String, dynamic> user) async {
    setState(() { _loadingUserBudget = true; _selectedUserBudget = null; });
    try {
      final r = await ApiClient.get('/api/admin/budget/user/${user['userId']}');
      if (r.statusCode == 200) setState(() { _selectedUserBudget = jsonDecode(r.body); });
    } catch (_) {}
    setState(() { _loadingUserBudget = false; });
    if (mounted) _showBudgetDetailSheet(user);
  }

  void _showBudgetDetailSheet(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeColors.cardBg(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          expand: false,
          builder: (_, sc) => _buildUserBudgetSheet(ctx, user, sc, setSheet),
        ),
      ),
    );
  }

  Widget _buildUserBudgetSheet(BuildContext ctx, Map<String, dynamic> user, ScrollController sc, StateSetter setSheet) {
    final cats = (_selectedUserBudget?['categories'] as List? ?? []);
    final controllers = <String, TextEditingController>{};
    for (final c in cats) {
      final cat = c['category'] as String;
      controllers[cat] = TextEditingController(text: (c['limit'] ?? '').toString());
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.account_circle_rounded, color: AppColors.cyan, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(user['email'] ?? '', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_loadingUserBudget)
          const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.cyan)))
        else
          Expanded(
            child: ListView(
              controller: sc,
              padding: const EdgeInsets.all(16),
              children: [
                Text('Set / Override Budget Limits', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppThemeColors.primaryText(ctx))),
                const SizedBox(height: 12),
                if (cats.isEmpty)
                  _addCategoryForm(ctx, user, controllers, setSheet)
                else ...[
                  ...cats.map((c) => _limitRow(c, controllers)),
                  const SizedBox(height: 8),
                  // Add new category row
                  _addCategoryForm(ctx, user, controllers, setSheet),
                ],
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_rounded, color: Colors.white),
                  label: const Text('Save Budget Overrides', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, minimumSize: const Size(double.infinity, 48)),
                  onPressed: () async {
                    final limits = <String, dynamic>{};
                    for (final e in controllers.entries) {
                      final v = double.tryParse(e.value.text.trim());
                      if (v != null && v >= 0) limits[e.key] = v;
                    }
                    final r = await ApiClient.patch(
                      '/api/admin/budget/user/${user['userId']}/limits',
                      body: {'limits': limits},
                    );
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(r.statusCode == 200 ? 'Budget limits updated!' : 'Failed to update limits'),
                        backgroundColor: r.statusCode == 200 ? Colors.green : Colors.red,
                      ));
                      _fetchUsers(reset: true);
                    }
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _limitRow(Map c, Map<String, TextEditingController> controllers) {
    final cat = c['category'] as String;
    final spent = (c['spent'] as num?)?.toDouble() ?? 0;
    final limit = (c['limit'] as num?)?.toDouble();
    final usedPct = limit != null && limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    final overBudget = limit != null && spent > limit;

    controllers.putIfAbsent(cat, () => TextEditingController(text: limit?.toStringAsFixed(0) ?? ''));

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(_capFirst(cat), style: const TextStyle(fontWeight: FontWeight.w600))),
              Text('Spent: ₹${_fmtN(spent)}', style: TextStyle(fontSize: 12, color: overBudget ? Colors.red : AppThemeColors.secondaryText(context))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controllers[cat],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    labelText: 'Limit for ${_capFirst(cat)}',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.cyan)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          if (limit != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: usedPct,
                minHeight: 6,
                color: overBudget ? Colors.red : AppColors.cyan,
                backgroundColor: AppThemeColors.border(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _addCategoryForm(BuildContext ctx, Map<String, dynamic> user, Map<String, TextEditingController> controllers, StateSetter setSheet) {
    final catController   = TextEditingController();
    final limitController = TextEditingController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Text('Add New Category', style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.secondaryText(ctx))),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: catController,
                decoration: InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: limitController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  labelText: 'Limit',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, padding: const EdgeInsets.all(14)),
              onPressed: () {
                final cat = catController.text.trim();
                final val = limitController.text.trim();
                if (cat.isNotEmpty && val.isNotEmpty) {
                  setSheet(() { controllers[cat] = TextEditingController(text: val); });
                  catController.clear();
                  limitController.clear();
                }
              },
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ],
        ),
      ],
    );
  }

  String _fmt(num? n) => n == null ? '–' : '₹${NumberFormat('#,##,###').format(n.round())}';
  String _fmtN(num? n) => n == null ? '0' : NumberFormat('#,##,###').format(n.round());
  String _capFirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Column(
        children: [
          SizedBox(
            height: 130,
            child: Stack(
              children: [
                ClipPath(
                  clipper: DeepTopWaveClipper(),
                  child: Container(
                    height: 130,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF2E7D32), AppColors.cyan],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Budget Management', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                            Text('User budgets & overrides', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                        const Spacer(),
                        const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 30),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          AppTabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: const [
              AppTabItem(label: 'Overview'),
              AppTabItem(label: 'User Budgets'),
              AppTabItem(label: 'Set Override'),
              AppTabItem(label: 'Subscriptions'),
              AppTabItem(label: 'Personal Budgets'),
              AppTabItem(label: 'PB History'),
            ],
          ),

          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildOverviewTab(),
                _buildUsersTab(),
                _buildOverrideTab(),
                _buildSubscriptionsTab(),
                _buildPersonalBudgetsTab(),
                _buildPersonalBudgetHistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    if (_loadingOverview) return const Center(child: CircularProgressIndicator(color: AppColors.cyan));
    if (_overviewErr != null) return _errorView(_overviewErr!, _fetchOverview);
    if (_overview == null) return const SizedBox();
    final o = _overview!;
    final cats = o['categories'] as List? ?? [];
    final recCats = o['recurringByCategory'] as List? ?? [];

    return RefreshIndicator(
      color: AppColors.cyan,
      onRefresh: _fetchOverview,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              _kpi('Total Users', '${o['totalUsers'] ?? 0}', Icons.people_rounded, Colors.indigo),
              _kpi('With Budget', '${o['usersWithBudget'] ?? 0}', Icons.pie_chart_rounded, Colors.green),
              _kpi('Adoption', '${o['budgetAdoptionPct'] ?? 0}%', Icons.trending_up_rounded, AppColors.cyan),
              _kpi('Compliance', '${o['complianceRate'] ?? 0}%', Icons.verified_rounded, Colors.teal),
              _kpi('Overspending', '${o['overspendingCount'] ?? 0}', Icons.warning_rounded, Colors.orange),
              _kpi('Recurring Items', '${o['recurringItemsCount'] ?? 0}', Icons.repeat_rounded, Colors.purple),
            ],
          ),
          const SizedBox(height: 20),

          _sectionHeader('Popular Budget Categories'),
          ...cats.take(6).map((c) => _card(Row(
            children: [
              Expanded(child: Text(_capFirst(c['category']?.toString() ?? ''), style: TextStyle(color: AppThemeColors.primaryText(context)))),
              Text('${c['usersWithLimit']} users', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
              const SizedBox(width: 12),
              Text(_fmt(c['avgLimit']), style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ))),

          if (recCats.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionHeader('Recurring by Category'),
            ...recCats.map((c) => _card(Row(
              children: [
                Expanded(child: Text(_capFirst(c['category']?.toString() ?? ''))),
                Text('${c['count']} items', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
                const SizedBox(width: 12),
                Text(_fmt(c['totalAmount']), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ))),
          ],
        ],
      ),
    );
  }

  Widget _buildUsersTab() {
    return Column(
      children: [
        AppSearchBar(
          controller: _searchController,
          hintText: 'Search by name or email…',
          onSubmit: () => _fetchUsers(reset: true),
          onChanged: (v) { if (v.isEmpty) _fetchUsers(reset: true); },
          margin: const EdgeInsets.all(12),
        ),
        if (_loadingUsers) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppColors.cyan)))
        else if (_usersErr != null) _errorView(_usersErr!, () => _fetchUsers(reset: true))
        else Expanded(
          child: RefreshIndicator(
            color: AppColors.cyan,
            onRefresh: () => _fetchUsers(reset: true),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _userRows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final u = _userRows[i] as Map<String, dynamic>;
                final isOver = u['isOver'] as bool? ?? false;
                final usedPct = (u['usedPct'] as num?)?.toInt();
                return InkWell(
                  onTap: () => _loadUserBudgetDetail(u),
                  borderRadius: BorderRadius.circular(14),
                  child: _card(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(u['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context))),
                                Text(u['email'] ?? '', style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                              ],
                            ),
                          ),
                          if (isOver)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                              child: const Text('Over Budget', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                            )
                          else if (u['hasBudget'] == true)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                              child: const Text('On Track', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                              child: const Text('No Budget', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                      if (u['hasBudget'] == true) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text('Spent: ${_fmt(u['spent'])}', style: const TextStyle(fontSize: 12)),
                            const Text(' / ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('Limit: ${_fmt(u['totalLimit'])}', style: const TextStyle(fontSize: 12)),
                            if (usedPct != null) ...[
                              const Spacer(),
                              Text('$usedPct%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isOver ? Colors.red : AppColors.cyan)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ((u['usedPct'] as num?)?.toDouble() ?? 0) / 100,
                            minHeight: 6,
                            color: isOver ? Colors.red : AppColors.cyan,
                            backgroundColor: AppThemeColors.border(context),
                          ),
                        ),
                      ],
                    ],
                  )),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _overrideSearch(String q) async {
    if (q.trim().isEmpty) {
      setState(() { _overrideResults = []; _overrideSearching = false; });
      return;
    }
    setState(() => _overrideSearching = true);
    try {
      final r = await ApiClient.get(
        '/api/admin/budget/users?search=${Uri.encodeComponent(q.trim())}&limit=6',
      );
      if (r.statusCode == 200 && mounted) {
        setState(() => _overrideResults = (jsonDecode(r.body)['rows'] as List? ?? []));
      }
    } catch (_) {}
    if (mounted) setState(() => _overrideSearching = false);
  }

  Widget _buildOverrideTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Search User',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15,
                    color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 4),
            Text('Find a user by name or email to override their monthly budget limits.',
                style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
            const SizedBox(height: 12),
            AppSearchBar(
              controller: _overrideSearchCtrl,
              hintText: 'Name or email…',
              onChanged: _overrideSearch,
              isLoading: _overrideSearching,
              margin: EdgeInsets.zero,
            ),
          ]),
        ),
        const SizedBox(height: 8),
        if (_overrideResults.isEmpty && _overrideSearchCtrl.text.isEmpty)
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.08), shape: BoxShape.circle),
                  child: const Icon(Icons.manage_search_rounded, size: 44, color: AppColors.cyan),
                ),
                const SizedBox(height: 14),
                Text('Search for a user', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600,
                    color: AppThemeColors.primaryText(context))),
                const SizedBox(height: 6),
                Text('Type a name or email above to find a user\nand set their budget limits directly.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
              ]),
            ),
          )
        else if (_overrideResults.isEmpty && !_overrideSearching)
          Expanded(
            child: Center(child: Text('No users found',
                style: TextStyle(color: AppThemeColors.secondaryText(context)))),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: _overrideResults.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final u = _overrideResults[i] as Map<String, dynamic>;
                final spent     = (u['spent']      as num?)?.toDouble() ?? 0;
                final limit     = (u['totalLimit'] as num?)?.toDouble() ?? 0;
                final hasBudget = u['hasBudget'] == true;
                final isOver    = u['isOver']    == true;
                final pct       = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
                final barColor  = isOver ? Colors.red : AppColors.cyan;

                return GestureDetector(
                  onTap: () => _loadUserBudgetDetail(u),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: isOver
                              ? Colors.red.withValues(alpha: 0.4)
                              : AppThemeColors.border(context)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                            color: AppColors.cyan.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.account_circle_rounded, color: AppColors.cyan, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(u['name'] ?? '', style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13,
                            color: AppThemeColors.primaryText(context))),
                        Text(u['email'] ?? '', style: TextStyle(
                            fontSize: 11, color: AppThemeColors.secondaryText(context))),
                        if (hasBudget) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: pct, minHeight: 4,
                              color: barColor,
                              backgroundColor: AppThemeColors.border(context),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isOver
                                ? '₹${spent.toStringAsFixed(0)} / ₹${limit.toStringAsFixed(0)} — Over budget'
                                : '₹${spent.toStringAsFixed(0)} / ₹${limit.toStringAsFixed(0)}',
                            style: TextStyle(fontSize: 10, color: barColor, fontWeight: FontWeight.w600),
                          ),
                        ] else
                          Text('No budget set', style: TextStyle(
                              fontSize: 10, color: AppThemeColors.secondaryText(context))),
                      ])),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: AppColors.cyan.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Text('Override',
                            style: TextStyle(fontSize: 10, color: AppColors.cyan, fontWeight: FontWeight.bold)),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSubscriptionsTab() {
    if (_loadingSubs) return const Center(child: CircularProgressIndicator(color: AppColors.cyan));
    if (_subsErr != null) return _errorView(_subsErr!, _fetchSubscriptions);
    if (_subscriptions.isEmpty) return _emptyView('No subscriptions tracked yet', Icons.subscriptions_outlined);

    return RefreshIndicator(
      color: AppColors.cyan,
      onRefresh: _fetchSubscriptions,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _subscriptions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final s = _subscriptions[i] as Map<String, dynamic>;
          final user = s['user'] as Map<String, dynamic>?;
          return _card(Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.repeat_rounded, color: Colors.purple, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context))),
                    if (user != null)
                      Text(user['email'] ?? '', style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_fmt(s['amount']), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                  if (s['dueDay'] != null)
                    Text('Due: Day ${s['dueDay']}', style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                ],
              ),
            ],
          ));
        },
      ),
    );
  }

  // ─── Personal Budgets tab (active, all users) ────────────────────────────

  Widget _buildPersonalBudgetsTab() {
    return Column(children: [
      AppSearchBar(
        controller: _pbActiveSearch,
        hintText: 'Search by user name or email…',
        onSubmit: () => _fetchPBActive(reset: true),
        onChanged: (v) { if (v.isEmpty) _fetchPBActive(reset: true); },
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      ),
      const SizedBox(height: 8),
      if (_loadingPBActive && _pbActive.isEmpty)
        const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.cyan)))
      else if (_pbActiveErr != null)
        Expanded(child: _errorView(_pbActiveErr!, () => _fetchPBActive(reset: true)))
      else if (_pbActive.isEmpty)
        Expanded(child: _emptyView('No active personal budgets', Icons.savings_outlined))
      else
        Expanded(
          child: RefreshIndicator(
            color: AppColors.cyan,
            onRefresh: () => _fetchPBActive(reset: true),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
              itemCount: _pbActive.length + (_pbActiveHasMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                if (i == _pbActive.length) {
                  return TextButton(
                    onPressed: _loadingPBActive ? null : _fetchPBActive,
                    child: _loadingPBActive
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan))
                        : const Text('Load more', style: TextStyle(color: AppColors.cyan)),
                  );
                }
                return _pbBudgetCard(_pbActive[i] as Map<String, dynamic>, isHistory: false);
              },
            ),
          ),
        ),
    ]);
  }

  // ─── Personal Budget History tab (completed/expired, all users) ──────────

  Widget _buildPersonalBudgetHistoryTab() {
    return Column(children: [
      AppSearchBar(
        controller: _pbHistorySearch,
        hintText: 'Search by user name or email…',
        onSubmit: () => _fetchPBHistory(reset: true),
        onChanged: (v) { if (v.isEmpty) _fetchPBHistory(reset: true); },
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      ),
      const SizedBox(height: 8),
      if (_loadingPBHistory && _pbHistory.isEmpty)
        const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.cyan)))
      else if (_pbHistoryErr != null)
        Expanded(child: _errorView(_pbHistoryErr!, () => _fetchPBHistory(reset: true)))
      else if (_pbHistory.isEmpty)
        Expanded(child: _emptyView('No budget history found', Icons.history_rounded))
      else
        Expanded(
          child: RefreshIndicator(
            color: AppColors.cyan,
            onRefresh: () => _fetchPBHistory(reset: true),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
              itemCount: _pbHistory.length + (_pbHistoryHasMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                if (i == _pbHistory.length) {
                  return TextButton(
                    onPressed: _loadingPBHistory ? null : _fetchPBHistory,
                    child: _loadingPBHistory
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan))
                        : const Text('Load more', style: TextStyle(color: AppColors.cyan)),
                  );
                }
                return _pbBudgetCard(_pbHistory[i] as Map<String, dynamic>, isHistory: true);
              },
            ),
          ),
        ),
    ]);
  }

  Widget _pbBudgetCard(Map<String, dynamic> b, {required bool isHistory}) {
    final user      = b['user'] as Map<String, dynamic>? ?? {};
    final budgetId  = b['_id'] as String? ?? '';
    final name      = b['name'] as String? ?? '';
    final currency  = b['currency'] as String? ?? 'INR';
    final limit     = (b['limit'] as num?)?.toDouble() ?? 0;
    final spent     = (b['spentAmount'] as num?)?.toDouble() ?? 0;
    final pct       = (b['percentSpent'] as num?)?.toDouble() ?? 0;
    final status    = b['status'] as String? ?? '';
    final period    = b['period'] as String? ?? '';
    final daysLeft  = (b['daysLeft'] as num?)?.toInt();
    final notes     = b['notes'] as String? ?? '';
    final df        = DateFormat('dd MMM yyyy');
    final startRaw  = b['startDate'] as String?;
    final endRaw    = b['endDate'] as String?;
    final startStr  = startRaw != null ? df.format(DateTime.parse(startRaw).toLocal()) : '';
    final endStr    = endRaw   != null ? df.format(DateTime.parse(endRaw).toLocal())   : '';
    final color     = pct >= 100 ? Colors.red.shade600 : pct >= 80 ? Colors.orange.shade600 : Colors.green.shade600;
    final stColor   = status == 'completed' ? Colors.green.shade600 : status == 'expired' ? Colors.orange.shade700 : AppColors.cyan;
    final expanded    = _expandedPBIds.contains(budgetId);
    final budgetColor = _colorFromBudget(budgetId);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: budgetColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: budgetColor.withValues(alpha: 0.45), width: 2),
        boxShadow: [BoxShadow(color: budgetColor.withValues(alpha: 0.12),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Always visible ──────────────────────────────────────────────────
      Row(children: [
        const Icon(Icons.account_circle_rounded, color: AppColors.cyan, size: 20),
        const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user['name'] as String? ?? '–',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: AppThemeColors.primaryText(context))),
          Text(user['email'] as String? ?? '',
              style: TextStyle(fontSize: 10, color: AppThemeColors.secondaryText(context))),
        ])),
        _pbChip(_capFirst(period), AppColors.cyan.withValues(alpha: 0.12), AppColors.cyan),
        const SizedBox(width: 4),
        if (isHistory)
          _pbChip(_capFirst(status), stColor.withValues(alpha: 0.12), stColor),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: Text(name,
            style: TextStyle(fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context)))),
        if (!isHistory && daysLeft != null)
          Text('$daysLeft days left',
              style: TextStyle(fontSize: 11,
                  color: daysLeft <= 3 ? Colors.red : AppThemeColors.secondaryText(context))),
        if (isHistory && endStr.isNotEmpty)
          Text('Ended $endStr',
              style: TextStyle(fontSize: 10, color: AppThemeColors.secondaryText(context))),
      ]),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('$currency ${_fmtN(spent)} / ${_fmtN(limit)}',
            style: TextStyle(fontSize: 12, color: AppThemeColors.primaryText(context))),
        Text('${pct.toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
        value: (pct / 100).clamp(0.0, 1.0), minHeight: 6,
        color: color, backgroundColor: AppThemeColors.border(context),
      )),

      // ── Expanded section ────────────────────────────────────────────────
      AnimatedCrossFade(
        duration: const Duration(milliseconds: 220),
        crossFadeState: expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
        firstChild: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          // Date range
          if (startStr.isNotEmpty || endStr.isNotEmpty)
            Row(children: [
              const Icon(Icons.date_range_rounded, size: 13, color: AppColors.cyan),
              const SizedBox(width: 4),
              Text('$startStr → $endStr',
                  style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
            ]),
          // Notes
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.notes_rounded, size: 13, color: AppColors.cyan),
              const SizedBox(width: 4),
              Expanded(child: Text(notes, maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context),
                      fontStyle: FontStyle.italic))),
            ]),
          ],
          // Over/under summary
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(pct >= 100 ? Icons.warning_rounded : Icons.check_circle_rounded,
                  size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(
                pct >= 100
                    ? 'Over budget by $currency ${_fmtN(spent - limit)}'
                    : 'Under budget — $currency ${_fmtN(limit - spent)} remaining',
                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
              )),
            ]),
          ),
          const SizedBox(height: 10),
          // View All Expenses button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.receipt_long_rounded, size: 16, color: AppColors.cyan),
              label: const Text('View All Expenses & Audit Trail',
                  style: TextStyle(color: AppColors.cyan, fontSize: 12, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.cyan),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: () => _showAdminExpensesSheet(budgetId, name, currency),
            ),
          ),
        ]),
        secondChild: const SizedBox.shrink(),
      ),

      // ── View More / View Less toggle ────────────────────────────────────
      const SizedBox(height: 6),
      GestureDetector(
        onTap: () => setState(() {
          if (expanded) _expandedPBIds.remove(budgetId);
          else _expandedPBIds.add(budgetId);
        }),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(expanded ? 'View Less' : 'View More',
              style: const TextStyle(fontSize: 12, color: AppColors.cyan,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              size: 16, color: AppColors.cyan),
        ]),
      ),
      ]),
    );
  }

  // ─── Admin expense sheet ─────────────────────────────────────────────────

  void _showAdminExpensesSheet(String budgetId, String budgetName, String currency) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeColors.cardBg(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AdminExpenseSheet(
          budgetId: budgetId, budgetName: budgetName, currency: currency),
    );
  }

  Widget _pbChip(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600)),
  );

  Widget _kpi(String label, String value, IconData icon, Color color) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
      Text(label, style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
    ]),
  );

  Widget _sectionHeader(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.cyan)),
  );

  Color _colorFromBudget(String id) {
    const palette = [
      Color(0xFF4CAF50), Color(0xFF2196F3), Color(0xFF9C27B0),
      Color(0xFFFF9800), Color(0xFFE91E63), Color(0xFF00BCD4),
      Color(0xFFFF5722), Color(0xFF607D8B), Color(0xFF795548), Color(0xFF3F51B5),
    ];
    final hash = id.codeUnits.fold(0, (prev, el) => prev + el);
    return palette[hash % palette.length];
  }

  Widget _card(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 2),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppThemeColors.border(context))),
    child: child,
  );

  Widget _errorView(String msg, VoidCallback retry) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.withValues(alpha: 0.7)),
    const SizedBox(height: 12),
    Text(msg, style: TextStyle(color: AppThemeColors.secondaryText(context))),
    const SizedBox(height: 12),
    ElevatedButton(onPressed: retry, style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan), child: const Text('Retry', style: TextStyle(color: Colors.white))),
  ]));

  Widget _emptyView(String msg, IconData icon) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 56, color: AppThemeColors.secondaryText(context).withValues(alpha: 0.5)),
    const SizedBox(height: 16),
    Text(msg, style: TextStyle(color: AppThemeColors.secondaryText(context))),
  ]));
}

// ─── Admin expense sheet (separate StatefulWidget) ───────────────────────────

class _AdminExpenseSheet extends StatefulWidget {
  final String budgetId;
  final String budgetName;
  final String currency;
  const _AdminExpenseSheet({
    required this.budgetId,
    required this.budgetName,
    required this.currency,
  });

  @override
  State<_AdminExpenseSheet> createState() => _AdminExpenseSheetState();
}

class _AdminExpenseSheetState extends State<_AdminExpenseSheet>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  List<dynamic> _active  = [];
  List<dynamic> _deleted = [];
  double _total = 0;
  late TabController _tabs;

  final _dtFmt = DateFormat('dd MMM yyyy, hh:mm a');
  final _numFmt = NumberFormat('#,##0.##', 'en_IN');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await ApiClient.get('/api/admin/personal-budget/${widget.budgetId}/expenses');
      if (!mounted) return;
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() {
          _active  = (d['active']  as List? ?? []);
          _deleted = (d['deleted'] as List? ?? []);
          _total   = (d['total']   as num?)?.toDouble() ?? 0;
        });
      } else {
        setState(() => _error = 'Failed to load expenses.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(num? v) => '${widget.currency} ${_numFmt.format(v ?? 0)}';

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, sc) => Column(children: [
        // Handle
        Container(margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2))),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            const Icon(Icons.receipt_long_rounded, color: AppColors.cyan, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.budgetName,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15,
                      color: AppThemeColors.primaryText(context))),
              Text('All expenses — ${_active.length} active · ${_deleted.length} deleted',
                  style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
            ])),
            if (!_loading)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Text('Total: ${_fmt(_total)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.cyan,
                        fontWeight: FontWeight.bold)),
              ),
          ]),
        ),
        // Tabs
        AppTabBar(
          controller: _tabs,
          tabs: [
            AppTabItem(label: 'Active', count: _active.length),
            AppTabItem(label: 'Deleted', count: _deleted.length),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
              : _error != null
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                      ElevatedButton(onPressed: _load,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan),
                          child: const Text('Retry', style: TextStyle(color: Colors.white))),
                    ]))
                  : TabBarView(controller: _tabs, children: [
                      _buildExpenseList(_active, deleted: false),
                      _buildExpenseList(_deleted, deleted: true),
                    ]),
        ),
      ]),
    );
  }

  Widget _buildExpenseList(List<dynamic> list, {required bool deleted}) {
    if (list.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(deleted ? Icons.delete_outline_rounded : Icons.receipt_long_rounded,
            size: 48, color: AppThemeColors.secondaryText(context).withValues(alpha: 0.4)),
        const SizedBox(height: 12),
        Text(deleted ? 'No deleted expenses' : 'No expenses yet',
            style: TextStyle(color: AppThemeColors.secondaryText(context))),
      ]));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _buildExpenseCard(list[i] as Map<String, dynamic>, deleted: deleted),
    );
  }

  Widget _buildExpenseCard(Map<String, dynamic> e, {required bool deleted}) {
    final amount   = (e['amount'] as num?)?.toDouble() ?? 0;
    final category = e['category'] as String? ?? '';
    final desc     = e['description'] as String? ?? '';
    final history  = (e['editHistory'] as List? ?? []);
    final dateRaw  = e['date'] as String?;
    final createdRaw  = e['createdAt'] as String?;
    final updatedRaw  = e['updatedAt'] as String?;
    final deletedRaw  = e['deletedAt'] as String?;
    final hasHistory  = history.isNotEmpty;

    final cardColor = deleted
        ? Colors.red.withValues(alpha: 0.06)
        : AppThemeColors.cardBg(context);
    final borderColor = deleted
        ? Colors.red.withValues(alpha: 0.3)
        : AppThemeColors.border(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Top row
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(category,
                style: const TextStyle(fontSize: 11, color: AppColors.cyan,
                    fontWeight: FontWeight.w600)),
          ),
          const Spacer(),
          Text(_fmt(amount),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                  color: deleted ? Colors.red.shade700 : AppThemeColors.primaryText(context))),
          if (deleted) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: const Text('DELETED',
                  style: TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(desc, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
        ],
        const SizedBox(height: 6),
        // Timestamps
        _tsRow(Icons.calendar_today_rounded, 'Expense date',
            dateRaw != null ? _dtFmt.format(DateTime.parse(dateRaw).toLocal()) : '–'),
        _tsRow(Icons.add_circle_outline_rounded, 'Created',
            createdRaw != null ? _dtFmt.format(DateTime.parse(createdRaw).toLocal()) : '–'),
        if (updatedRaw != null && updatedRaw != createdRaw)
          _tsRow(Icons.edit_rounded, 'Last edited',
              _dtFmt.format(DateTime.parse(updatedRaw).toLocal())),
        if (deletedRaw != null)
          _tsRow(Icons.delete_rounded, 'Deleted at',
              _dtFmt.format(DateTime.parse(deletedRaw).toLocal()), color: Colors.red),

        // Edit history
        if (hasHistory) ...[
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.history_rounded, size: 13, color: AppColors.cyan),
            const SizedBox(width: 4),
            Text('Edit History (${history.length} version${history.length == 1 ? '' : 's'})',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: AppColors.cyan)),
          ]),
          const SizedBox(height: 6),
          ...history.asMap().entries.map((entry) {
            final idx = entry.key;
            final h   = entry.value as Map<String, dynamic>;
            final editedAt = h['editedAt'] as String?;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cyan.withValues(alpha: 0.15)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('v${idx + 1}',
                        style: const TextStyle(fontSize: 9, color: AppColors.cyan,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 6),
                  Text(_fmt(h['amount'] as num?),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text(h['category'] as String? ?? '',
                      style: const TextStyle(fontSize: 11, color: AppColors.cyan)),
                  const Spacer(),
                  if (editedAt != null)
                    Text(_dtFmt.format(DateTime.parse(editedAt).toLocal()),
                        style: TextStyle(fontSize: 9,
                            color: AppThemeColors.secondaryText(context))),
                ]),
                if ((h['description'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(h['description'] as String,
                      style: TextStyle(fontSize: 11,
                          color: AppThemeColors.secondaryText(context))),
                ],
              ]),
            );
          }),
        ],
      ]),
    );
  }

  Widget _tsRow(IconData icon, String label, String value, {Color? color}) {
    final c = color ?? AppThemeColors.secondaryText(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(children: [
        Icon(icon, size: 11, color: c),
        const SizedBox(width: 4),
        Text('$label: ', style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w500)),
        Expanded(child: Text(value, style: TextStyle(fontSize: 10, color: c),
            overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}
