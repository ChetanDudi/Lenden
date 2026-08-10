import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../widgets/app_colors.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/search_tab_bar.dart';

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  Map<String, dynamic>? _platform;
  List<dynamic> _topUsers = [];
  List<dynamic> _categoryTrends = [];

  bool _loadingPlatform = false;
  bool _loadingTopUsers = false;
  bool _loadingTrends = false;

  String? _platformErr;
  String? _topUsersErr;
  String? _trendsErr;

  // User lookup
  final _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _searching = false;
  Map<String, dynamic>? _userReport;
  bool _loadingUserReport = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        switch (_tabs.index) {
          case 0:
            if (_platform == null) _fetchPlatform();
            break;
          case 1:
            if (_topUsers.isEmpty) _fetchTopUsers();
            break;
          case 2:
            if (_categoryTrends.isEmpty) _fetchTrends();
            break;
        }
      }
    });
    _fetchPlatform();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchPlatform() async {
    setState(() { _loadingPlatform = true; _platformErr = null; });
    try {
      final r = await ApiClient.get('/api/admin/reports/platform');
      if (r.statusCode == 200) {
        setState(() { _platform = jsonDecode(r.body); });
      } else {
        setState(() { _platformErr = 'Failed to load platform report'; });
      }
    } catch (e) {
      setState(() { _platformErr = 'Error: $e'; });
    } finally {
      setState(() { _loadingPlatform = false; });
    }
  }

  Future<void> _fetchTopUsers() async {
    setState(() { _loadingTopUsers = true; _topUsersErr = null; });
    try {
      final r = await ApiClient.get('/api/admin/reports/top-users?limit=20');
      if (r.statusCode == 200) {
        setState(() { _topUsers = jsonDecode(r.body)['topUsers'] ?? []; });
      } else {
        setState(() { _topUsersErr = 'Failed to load top users'; });
      }
    } catch (e) {
      setState(() { _topUsersErr = 'Error: $e'; });
    } finally {
      setState(() { _loadingTopUsers = false; });
    }
  }

  Future<void> _fetchTrends() async {
    setState(() { _loadingTrends = true; _trendsErr = null; });
    try {
      final r = await ApiClient.get('/api/admin/reports/category-trends');
      if (r.statusCode == 200) {
        setState(() { _categoryTrends = jsonDecode(r.body)['trends'] ?? []; });
      } else {
        setState(() { _trendsErr = 'Failed to load trends'; });
      }
    } catch (e) {
      setState(() { _trendsErr = 'Error: $e'; });
    } finally {
      setState(() { _loadingTrends = false; });
    }
  }

  Future<void> _searchUsers(String q) async {
    if (q.trim().isEmpty) { setState(() { _searchResults = []; }); return; }
    setState(() { _searching = true; });
    try {
      final r = await ApiClient.get('/api/admin/reports/search-users?q=${Uri.encodeComponent(q)}');
      if (r.statusCode == 200) {
        setState(() { _searchResults = jsonDecode(r.body)['users'] ?? []; });
      }
    } catch (_) {}
    setState(() { _searching = false; });
  }

  Future<void> _fetchUserReport(String userId) async {
    setState(() { _loadingUserReport = true; _userReport = null; _searchResults = []; _searchController.clear(); });
    try {
      final r = await ApiClient.get('/api/admin/reports/user/$userId');
      if (r.statusCode == 200) {
        setState(() { _userReport = jsonDecode(r.body); });
      }
    } catch (_) {}
    setState(() { _loadingUserReport = false; });
  }

  String _fmt(num? n) => n == null ? '–' : '₹${NumberFormat('#,##,###').format(n.round())}';
  String _fmtN(num? n) => n == null ? '–' : NumberFormat('#,##,###').format(n.round());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Column(
        children: [
          // Wave header
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
                        colors: [AppColors.cyan, Color(0xFF0288D1)],
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Platform Reports',
                                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                            Text('Analytics & Insights', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                          ],
                        ),
                        const Spacer(),
                        const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 32),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tabs
          AppTabBar(
            controller: _tabs,
            tabs: const [
              AppTabItem(label: 'Platform'),
              AppTabItem(label: 'Top Users'),
              AppTabItem(label: 'Categories'),
              AppTabItem(label: 'User Lookup'),
            ],
          ),

          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildPlatformTab(),
                _buildTopUsersTab(),
                _buildCategoryTrendsTab(),
                _buildUserLookupTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformTab() {
    if (_loadingPlatform) return const Center(child: CircularProgressIndicator(color: AppColors.cyan));
    if (_platformErr != null) return _errorView(_platformErr!, _fetchPlatform);
    if (_platform == null) return const SizedBox();
    final s = _platform!['summary'] as Map<String, dynamic>? ?? {};
    final trends = _platform!['monthlyTrend'] as List? ?? [];
    final cats = _platform!['categories'] as List? ?? [];

    return RefreshIndicator(
      color: AppColors.cyan,
      onRefresh: _fetchPlatform,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // KPI grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              _kpiCard('Total Users', _fmtN(s['totalUsers']), Icons.people_rounded, Colors.indigo),
              _kpiCard('Total Volume', _fmt(s['totalVolume']), Icons.currency_rupee_rounded, Colors.green),
              _kpiCard('Quick Txns', _fmtN(s['quickTransactions']), Icons.flash_on_rounded, AppColors.cyan),
              _kpiCard('Secure Txns', _fmtN(s['secureTransactions']), Icons.verified_rounded, Colors.orange),
              _kpiCard('Avg Txn Size', _fmt(s['avgTransactionSize']), Icons.analytics_rounded, Colors.purple),
              _kpiCard('Max Txn', _fmt(s['maxTransactionSize']), Icons.trending_up_rounded, Colors.red),
            ],
          ),
          const SizedBox(height: 20),

          // Volume split
          _sectionHeader('Volume Breakdown'),
          _card(Column(
            children: [
              _statRow('Quick Lent', _fmt(s['quickLent']), Colors.green),
              _statRow('Quick Borrowed', _fmt(s['quickBorrowed']), Colors.orange),
              _statRow('Secure Lent', _fmt(s['secureLent']), Colors.blue),
              _statRow('Secure Borrowed', _fmt(s['secureBorrowed']), Colors.red),
              _statRow('Group Volume', _fmt(s['groupVolume']), Colors.purple),
            ],
          )),
          const SizedBox(height: 20),

          // Monthly trend
          if (trends.isNotEmpty) ...[
            _sectionHeader('Monthly Trend (last 6 months)'),
            _card(_buildMonthlyTrend(trends)),
            const SizedBox(height: 20),
          ],

          // Category breakdown
          if (cats.isNotEmpty) ...[
            _sectionHeader('Top Categories'),
            ...cats.take(8).map((c) => _categoryRow(c)),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthlyTrend(List trends) {
    final maxVol = trends.fold<double>(0, (m, t) {
      final v = ((t['quick'] as num? ?? 0) + (t['secure'] as num? ?? 0)).toDouble();
      return v > m ? v : m;
    });
    return Column(
      children: trends.map<Widget>((t) {
        final vol = ((t['quick'] as num? ?? 0) + (t['secure'] as num? ?? 0)).toDouble();
        final pct = maxVol > 0 ? vol / maxVol : 0.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(width: 36, child: Text(t['label'] ?? '', style: const TextStyle(fontSize: 12))),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 18,
                    backgroundColor: AppThemeColors.border(context),
                    color: AppColors.cyan,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(_fmt(vol), style: const TextStyle(fontSize: 12)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTopUsersTab() {
    if (_loadingTopUsers) return const Center(child: CircularProgressIndicator(color: AppColors.cyan));
    if (_topUsersErr != null) return _errorView(_topUsersErr!, _fetchTopUsers);
    if (_topUsers.isEmpty) return _emptyView('No transaction data available', Icons.people_outline_rounded);

    return RefreshIndicator(
      color: AppColors.cyan,
      onRefresh: _fetchTopUsers,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _topUsers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final u = _topUsers[i];
          return _card(Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                child: Text('${i + 1}', style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u['name'] ?? u['email'] ?? '',
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context))),
                    Text(u['email'] ?? '', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_fmt(u['volume']), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.cyan)),
                  Text('${u['count']} txns', style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                ],
              ),
            ],
          ));
        },
      ),
    );
  }

  Widget _buildCategoryTrendsTab() {
    if (_loadingTrends) return const Center(child: CircularProgressIndicator(color: AppColors.cyan));
    if (_trendsErr != null) return _errorView(_trendsErr!, _fetchTrends);
    if (_categoryTrends.isEmpty) return _emptyView('No category data available', Icons.category_outlined);

    return RefreshIndicator(
      color: AppColors.cyan,
      onRefresh: _fetchTrends,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _categoryTrends.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final c = _categoryTrends[i] as Map<String, dynamic>;
          final change = c['change'] as num?;
          final up = change != null && change > 0;
          final chColor = change == null ? Colors.grey : (up ? Colors.red : Colors.green);
          return _card(Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.category_rounded, color: AppColors.cyan, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_capFirst(c['category']?.toString() ?? ''),
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context))),
                    Text('Last month: ${_fmt(c['lastMonth'])}',
                        style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_fmt(c['thisMonth']), style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (change != null)
                    Text('${up ? '+' : ''}$change%',
                        style: TextStyle(fontSize: 12, color: chColor, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ));
        },
      ),
    );
  }

  Widget _buildUserLookupTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by name or email…',
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.cyan),
              suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan))) : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.cyan)),
            ),
            onChanged: (q) => _searchUsers(q),
          ),
        ),
        if (_searchResults.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppThemeColors.border(context)),
            ),
            child: Column(
              children: _searchResults.map<Widget>((u) => ListTile(
                leading: const Icon(Icons.person_rounded, color: AppColors.cyan),
                title: Text(u['name'] ?? u['email'] ?? ''),
                subtitle: Text(u['email'] ?? ''),
                onTap: () => _fetchUserReport(u['_id']),
              )).toList(),
            ),
          ),
        if (_loadingUserReport)
          const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.cyan)))
        else if (_userReport != null)
          Expanded(child: _buildUserReportDetail(_userReport!))
        else
          Expanded(child: _emptyView('Search a user to view their report', Icons.person_search_rounded)),
      ],
    );
  }

  Widget _buildUserReportDetail(Map<String, dynamic> report) {
    final user = report['user'] as Map<String, dynamic>? ?? {};
    final quick = report['quick'] as Map<String, dynamic>? ?? {};
    final secure = report['secure'] as Map<String, dynamic>? ?? {};
    final cats = report['categories'] as List? ?? [];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // User header
        _card(Row(
          children: [
            const Icon(Icons.person_rounded, color: AppColors.cyan, size: 40),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user['name'] ?? 'Unknown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppThemeColors.primaryText(context))),
                Text(user['email'] ?? '', style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context))),
              ],
            ),
          ],
        )),
        const SizedBox(height: 12),

        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.6,
          children: [
            _kpiCard('Total Volume', _fmt(report['totalVolume']), Icons.currency_rupee_rounded, Colors.green),
            _kpiCard('Net Balance', _fmt(report['netBalance']), Icons.balance_rounded, Colors.blue),
            _kpiCard('Quick Lent', _fmt(quick['lent']), Icons.arrow_upward_rounded, Colors.teal),
            _kpiCard('Quick Borrowed', _fmt(quick['borrowed']), Icons.arrow_downward_rounded, Colors.orange),
            _kpiCard('Secure Lent', _fmt(secure['lent']), Icons.verified_rounded, Colors.indigo),
            _kpiCard('Secure Borrowed', _fmt(secure['borrowed']), Icons.account_balance_rounded, Colors.red),
          ],
        ),
        const SizedBox(height: 16),

        if (cats.isNotEmpty) ...[
          _sectionHeader('Category Breakdown'),
          ...cats.map((c) => _categoryRow(c)),
        ],
      ],
    );
  }

  Widget _categoryRow(Map c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _card(Row(
        children: [
          Text(_capFirst(c['category']?.toString() ?? ''),
              style: TextStyle(fontWeight: FontWeight.w500, color: AppThemeColors.primaryText(context))),
          const Spacer(),
          Text(_fmt(c['amount']), style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      )),
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.cyan)),
  );

  Widget _statRow(String label, String value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Container(width: 4, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(color: AppThemeColors.primaryText(context)))),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ],
    ),
  );

  Widget _card(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 2),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppThemeColors.cardBg(context),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppThemeColors.border(context)),
    ),
    child: child,
  );

  Widget _errorView(String msg, VoidCallback retry) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.withValues(alpha: 0.7)),
      const SizedBox(height: 12),
      Text(msg, style: TextStyle(color: AppThemeColors.secondaryText(context))),
      const SizedBox(height: 12),
      ElevatedButton(onPressed: retry, style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan), child: const Text('Retry', style: TextStyle(color: Colors.white))),
    ]),
  );

  Widget _emptyView(String msg, IconData icon) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 56, color: AppThemeColors.secondaryText(context).withValues(alpha: 0.5)),
      const SizedBox(height: 16),
      Text(msg, style: TextStyle(color: AppThemeColors.secondaryText(context))),
    ]),
  );

  String _capFirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
