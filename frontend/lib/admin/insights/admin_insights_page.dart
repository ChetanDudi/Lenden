import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../widgets/app_colors.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/search_tab_bar.dart';

class AdminInsightsPage extends StatefulWidget {
  const AdminInsightsPage({super.key});

  @override
  State<AdminInsightsPage> createState() => _AdminInsightsPageState();
}

class _AdminInsightsPageState extends State<AdminInsightsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  Map<String, dynamic>? _platform;
  bool _loadingPlatform = false;
  String? _platformErr;

  List<dynamic> _healthScores = [];
  bool _loadingHealth = false;
  String? _healthErr;

  List<dynamic> _anomalies = [];
  bool _loadingAnomalies = false;
  String? _anomaliesErr;

  List<dynamic> _tips = [];
  bool _loadingTips = false;
  String? _tipsErr;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        switch (_tabs.index) {
          case 0: if (_platform == null) _fetchPlatform(); break;
          case 1: if (_healthScores.isEmpty) _fetchHealth(); break;
          case 2: if (_anomalies.isEmpty) _fetchAnomalies(); break;
          case 3: if (_tips.isEmpty) _fetchTips(); break;
        }
      }
    });
    _fetchPlatform();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _fetchPlatform() async {
    setState(() { _loadingPlatform = true; _platformErr = null; });
    try {
      final r = await ApiClient.get('/api/admin/insights/platform');
      if (r.statusCode == 200) setState(() { _platform = jsonDecode(r.body); });
      else setState(() { _platformErr = 'Failed to load platform insights'; });
    } catch (e) { setState(() { _platformErr = 'Error: $e'; }); }
    setState(() { _loadingPlatform = false; });
  }

  Future<void> _fetchHealth() async {
    setState(() { _loadingHealth = true; _healthErr = null; });
    try {
      final r = await ApiClient.get('/api/admin/insights/health-scores?limit=30');
      if (r.statusCode == 200) setState(() { _healthScores = jsonDecode(r.body)['users'] ?? []; });
      else setState(() { _healthErr = 'Failed to load health scores'; });
    } catch (e) { setState(() { _healthErr = 'Error: $e'; }); }
    setState(() { _loadingHealth = false; });
  }

  Future<void> _fetchAnomalies() async {
    setState(() { _loadingAnomalies = true; _anomaliesErr = null; });
    try {
      final r = await ApiClient.get('/api/admin/insights/anomalies');
      if (r.statusCode == 200) setState(() { _anomalies = jsonDecode(r.body)['anomalies'] ?? []; });
      else setState(() { _anomaliesErr = 'Failed to load anomalies'; });
    } catch (e) { setState(() { _anomaliesErr = 'Error: $e'; }); }
    setState(() { _loadingAnomalies = false; });
  }

  Future<void> _fetchTips() async {
    setState(() { _loadingTips = true; _tipsErr = null; });
    try {
      final r = await ApiClient.get('/api/admin/insights/tips');
      if (r.statusCode == 200) setState(() { _tips = jsonDecode(r.body)['tips'] ?? []; });
      else setState(() { _tipsErr = 'Failed to load tips'; });
    } catch (e) { setState(() { _tipsErr = 'Error: $e'; }); }
    setState(() { _loadingTips = false; });
  }

  Future<void> _toggleTip(String id, bool current) async {
    final r = await ApiClient.patch('/api/admin/insights/tips/$id/toggle');
    if (r.statusCode == 200) _fetchTips();
  }

  Future<void> _deleteTip(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Tip'),
        content: const Text('Are you sure you want to delete this tip?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final r = await ApiClient.delete('/api/admin/insights/tips/$id');
      if (r.statusCode == 200 && mounted) _fetchTips();
    }
  }

  void _showCreateTipSheet() {
    final titleCtrl   = TextEditingController();
    final bodyCtrl    = TextEditingController();
    final savingCtrl  = TextEditingController();
    String impact     = 'medium';
    String targetType = 'all';
    String category   = 'general';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeColors.cardBg(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('Create Admin Tip', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.cyan)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Title *',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.cyan)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Body (tip content) *',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.cyan)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: impact,
                      decoration: InputDecoration(labelText: 'Impact', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                      items: const [
                        DropdownMenuItem(value: 'high',   child: Text('High')),
                        DropdownMenuItem(value: 'medium', child: Text('Medium')),
                        DropdownMenuItem(value: 'low',    child: Text('Low')),
                      ],
                      onChanged: (v) { if (v != null) setSheet(() => impact = v); },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: targetType,
                      decoration: InputDecoration(labelText: 'Target', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                      items: const [
                        DropdownMenuItem(value: 'all',     child: Text('All Users')),
                        DropdownMenuItem(value: 'premium', child: Text('Premium')),
                      ],
                      onChanged: (v) { if (v != null) setSheet(() => targetType = v); },
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: savingCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        prefixText: '₹ ',
                        labelText: 'Potential Saving (optional)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      onChanged: (v) => category = v.trim().isEmpty ? 'general' : v.trim(),
                      decoration: InputDecoration(
                        labelText: 'Category',
                        hintText: 'general',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  label: const Text('Publish Tip', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, minimumSize: const Size(double.infinity, 48)),
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty || bodyCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title and body are required')));
                      return;
                    }
                    final savingVal = double.tryParse(savingCtrl.text.trim());
                    final payload = <String, dynamic>{
                      'title':      titleCtrl.text.trim(),
                      'body':       bodyCtrl.text.trim(),
                      'impact':     impact,
                      'targetType': targetType,
                      'category':   category,
                      if (savingVal != null) 'potentialSaving': savingVal,
                    };
                    final r = await ApiClient.post('/api/admin/insights/tips', body: payload);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(r.statusCode == 201 ? 'Tip published!' : 'Failed to create tip'),
                        backgroundColor: r.statusCode == 201 ? Colors.green : Colors.red,
                      ));
                      if (r.statusCode == 201) _fetchTips();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(num? n) => n == null ? '–' : '₹${NumberFormat('#,##,###').format(n.round())}';

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
                        colors: [Color(0xFF6A1B9A), AppColors.cyan],
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
                            Text('Smart Insights Admin', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                            Text('Health scores, anomalies & tips', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                        const Spacer(),
                        const Icon(Icons.insights_rounded, color: Colors.white, size: 30),
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
            tabs: const [
              AppTabItem(label: 'Platform'),
              AppTabItem(label: 'Health Scores'),
              AppTabItem(label: 'Anomalies'),
              AppTabItem(label: 'Manage Tips'),
            ],
          ),

          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildPlatformTab(),
                _buildHealthTab(),
                _buildAnomaliesTab(),
                _buildTipsTab(),
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
    final p = _platform!;
    final topCats = p['topCategories'] as List? ?? [];

    return RefreshIndicator(
      color: AppColors.cyan,
      onRefresh: _fetchPlatform,
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
              _kpi('Total Users', '${p['totalUsers'] ?? 0}', Icons.people_rounded, Colors.indigo),
              _kpi('Avg Health', '${p['avgHealthScore'] ?? 0}%', Icons.favorite_rounded, Colors.pink),
              _kpi('With Budget', '${p['usersWithBudget'] ?? 0}', Icons.pie_chart_rounded, Colors.green),
              _kpi('Anomalies', '${p['anomalyCount'] ?? 0}', Icons.warning_rounded, Colors.orange),
              _kpi('Active Tips', '${p['activeAdminTips'] ?? 0}', Icons.lightbulb_rounded, Colors.amber),
              _kpi('Vol Change', '${p['volumeChange'] != null ? '${p['volumeChange']}%' : '–'}', Icons.trending_up_rounded, AppColors.cyan),
            ],
          ),
          const SizedBox(height: 20),

          _sectionHeader('Volume This Month'),
          _card(Column(children: [
            _statRow('This Month', _fmt(p['volumeThisMonth']), AppColors.cyan),
            _statRow('Last Month', _fmt(p['volumeLastMonth']), Colors.grey),
            _statRow('Transactions', '${p['txnCountThisMonth'] ?? 0}', Colors.blue),
          ])),
          const SizedBox(height: 20),

          if (topCats.isNotEmpty) ...[
            _sectionHeader('Top Spending Categories'),
            ...topCats.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _card(Row(
                children: [
                  Text(_capFirst(c['category']?.toString() ?? ''), style: TextStyle(color: AppThemeColors.primaryText(context))),
                  const Spacer(),
                  Text(_fmt(c['amount']), style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              )),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildHealthTab() {
    if (_loadingHealth) return const Center(child: CircularProgressIndicator(color: AppColors.cyan));
    if (_healthErr != null) return _errorView(_healthErr!, _fetchHealth);
    if (_healthScores.isEmpty) return _emptyView('No user data available', Icons.favorite_border_rounded);

    return RefreshIndicator(
      color: AppColors.cyan,
      onRefresh: _fetchHealth,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _healthScores.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final u = _healthScores[i] as Map<String, dynamic>;
          final score = (u['score'] as num?)?.toInt() ?? 50;
          final scoreColor = score >= 75 ? Colors.green : score >= 50 ? Colors.orange : Colors.red;

          return _card(Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 44, height: 44,
                    child: CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 4,
                      color: scoreColor,
                      backgroundColor: AppThemeColors.border(context),
                    ),
                  ),
                  Text('$score', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: scoreColor)),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context))),
                    Text(u['email'] ?? '', style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Spent: ${_fmt(u['spent'])}', style: const TextStyle(fontSize: 12)),
                  if (u['hasBudget'] == true)
                    Text('Limit: ${_fmt(u['budget'])}', style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                ],
              ),
            ],
          ));
        },
      ),
    );
  }

  Widget _buildAnomaliesTab() {
    if (_loadingAnomalies) return const Center(child: CircularProgressIndicator(color: AppColors.cyan));
    if (_anomaliesErr != null) return _errorView(_anomaliesErr!, _fetchAnomalies);
    if (_anomalies.isEmpty) return _emptyView('No anomalies detected', Icons.check_circle_outline_rounded);

    return RefreshIndicator(
      color: AppColors.cyan,
      onRefresh: _fetchAnomalies,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _anomalies.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final a = _anomalies[i] as Map<String, dynamic>;
          final type = a['type'] as String? ?? '';
          final overPct = a['overBudgetPct'] as num?;
          final momChange = a['momChange'] as num?;
          final isOverBudget = type == 'over_budget';

          return _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(isOverBudget ? Icons.warning_rounded : Icons.trending_up_rounded,
                      color: isOverBudget ? Colors.red : Colors.orange, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context))),
                        Text(a['email'] ?? '', style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isOverBudget ? Colors.red : Colors.orange).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(isOverBudget ? 'Over Budget' : 'Spending Spike',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isOverBudget ? Colors.red : Colors.orange)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _miniStat('Spent', _fmt(a['spent']))),
                if (a['budgetLimit'] != null && (a['budgetLimit'] as num) > 0)
                  Expanded(child: _miniStat('Limit', _fmt(a['budgetLimit']))),
                if (overPct != null) Expanded(child: _miniStat('Over', '+$overPct%', color: Colors.red)),
                if (momChange != null) Expanded(child: _miniStat('vs Last Month', '${momChange > 0 ? '+' : ''}$momChange%', color: Colors.orange)),
              ]),
            ],
          ));
        },
      ),
    );
  }

  Widget _buildTipsTab() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateTipSheet,
        backgroundColor: AppColors.cyan,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('New Tip', style: TextStyle(color: Colors.white)),
      ),
      body: _loadingTips
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
          : _tipsErr != null
              ? _errorView(_tipsErr!, _fetchTips)
              : _tips.isEmpty
                  ? _emptyView('No tips yet. Create one!', Icons.lightbulb_outline_rounded)
                  : RefreshIndicator(
                      color: AppColors.cyan,
                      onRefresh: _fetchTips,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                        itemCount: _tips.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) => _buildTipCard(_tips[i] as Map<String, dynamic>),
                      ),
                    ),
    );
  }

  Widget _buildTipCard(Map<String, dynamic> tip) {
    final isActive = tip['isActive'] as bool? ?? true;
    final impact   = tip['impact'] as String? ?? 'medium';
    final impactColor = impact == 'high' ? Colors.red : impact == 'medium' ? Colors.orange : Colors.green;
    final sender   = tip['sentBy'] as Map<String, dynamic>?;
    final target   = tip['targetType'] as String? ?? 'all';

    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: impactColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text(_capFirst(impact), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: impactColor)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(_capFirst(target), style: const TextStyle(fontSize: 11, color: AppColors.cyan)),
            ),
            const Spacer(),
            Switch(
              value: isActive,
              activeColor: AppColors.cyan,
              onChanged: (_) => _toggleTip(tip['_id'] as String, isActive),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(tip['title'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 4),
        Text(tip['body'] ?? '', style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 8),
        Row(
          children: [
            if (tip['potentialSaving'] != null)
              Text('Saves ~${_fmt(tip['potentialSaving'])}', style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (sender != null)
              Text('by ${sender['name'] ?? sender['email'] ?? ''}',
                  style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
              onPressed: () => _deleteTip(tip['_id'] as String),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ],
    ));
  }

  Widget _miniStat(String label, String value, {Color? color}) => Column(
    children: [
      Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color ?? AppThemeColors.primaryText(context))),
      Text(label, style: TextStyle(fontSize: 10, color: AppThemeColors.secondaryText(context))),
    ],
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

  Widget _statRow(String label, String value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Container(width: 4, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: TextStyle(color: AppThemeColors.primaryText(context)))),
      Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
    ]),
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

  String _capFirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
