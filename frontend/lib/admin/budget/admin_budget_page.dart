import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../widgets/app_colors.dart';
import '../../utils/theme_helper.dart';

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

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        switch (_tabs.index) {
          case 0: if (_overview == null) _fetchOverview(); break;
          case 1: if (_userRows.isEmpty) _fetchUsers(); break;
          case 3: if (_subscriptions.isEmpty) _fetchSubscriptions(); break;
        }
      }
    });
    _fetchOverview();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
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

          Container(
            color: AppThemeColors.cardBg(context),
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              labelColor: AppColors.cyan,
              unselectedLabelColor: AppThemeColors.secondaryText(context),
              indicatorColor: AppColors.cyan,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'User Budgets'),
                Tab(text: 'Set Override'),
                Tab(text: 'Subscriptions'),
              ],
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildOverviewTab(),
                _buildUsersTab(),
                _buildOverrideTab(),
                _buildSubscriptionsTab(),
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
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by name or email…',
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.cyan),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.cyan)),
            ),
            onSubmitted: (_) => _fetchUsers(reset: true),
            onChanged: (v) { if (v.isEmpty) _fetchUsers(reset: true); },
          ),
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

  Widget _buildOverrideTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cyan.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.cyan),
              const SizedBox(width: 10),
              Expanded(child: Text('To override a user\'s budget limits, go to the User Budgets tab, tap a user, and set limits per category.',
                  style: TextStyle(color: AppThemeColors.primaryText(context)))),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          icon: const Icon(Icons.people_rounded, color: Colors.white),
          label: const Text('Go to User Budgets', style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, minimumSize: const Size(double.infinity, 48)),
          onPressed: () => _tabs.animateTo(1),
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
