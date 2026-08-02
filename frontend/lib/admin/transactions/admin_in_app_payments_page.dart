import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../widgets/app_colors.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';

// ── Category metadata ─────────────────────────────────────────────────────────

class _Cat {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  const _Cat(this.key, this.label, this.icon, this.color);
}

const List<_Cat> _kCats = [
  _Cat('all',          'All',          Icons.swap_horiz_rounded,            AppColors.cyan),
  _Cat('p2p',          'P2P',          Icons.people_alt_rounded,            Color(0xFF1E88E5)),
  _Cat('quick',        'Quick Tx',     Icons.flash_on_rounded,              Color(0xFFFB8C00)),
  _Cat('secure',       'Secure Tx',    Icons.shield_rounded,                Color(0xFF43A047)),
  _Cat('group',        'Group',        Icons.group_work_rounded,            Color(0xFF8E24AA)),
  _Cat('qr',           'QR/Scan',      Icons.qr_code_2_rounded,             Color(0xFF00897B)),
  _Cat('subscription', 'Plans',        Icons.workspace_premium_rounded,     Color(0xFFE53935)),
  _Cat('coins',        'Coins',        Icons.toll_rounded,                  Color(0xFFFFB300)),
  _Cat('rewards',      'Rewards',      Icons.stars_rounded,                 Color(0xFF6A1B9A)),
  _Cat('gift_cards',   'Gift Cards',   Icons.card_giftcard_rounded,         Color(0xFFE91E63)),
  _Cat('offer_coins',  'Offer Coins',  Icons.local_offer_rounded,           Color(0xFF009688)),
  _Cat('referrals',    'Referrals',    Icons.group_add_rounded,             Color(0xFF9C27B0)),
  _Cat('refunds',      'Refunds',      Icons.undo_rounded,                  Color(0xFF00BCD4)),
];

// ── Main page ─────────────────────────────────────────────────────────────────

class AdminInAppPaymentsPage extends StatefulWidget {
  const AdminInAppPaymentsPage({super.key});

  @override
  State<AdminInAppPaymentsPage> createState() => _AdminInAppPaymentsPageState();
}

class _AdminInAppPaymentsPageState extends State<AdminInAppPaymentsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Map<String, int> _catCounts = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _kCats.length, vsync: this);
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final res = await ApiClient.get('/api/admin/in-app-transactions/counts');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _catCounts = data.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text('In-App Transfers',
            style: TextStyle(
                color: AppThemeColors.primaryText(context),
                fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.cyan,
          labelColor: AppColors.cyan,
          unselectedLabelColor: AppThemeColors.secondaryText(context),
          indicatorWeight: 3,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _kCats.map((c) {
            final count = _catCounts[c.key];
            final hasCount = count != null && count > 0;
            return Tab(
              icon: hasCount
                  ? Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(c.icon, size: 16),
                        Positioned(
                          top: -6,
                          right: -8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                            decoration: BoxDecoration(
                              color: c.color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              count > 99 ? '99+' : count.toString(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Icon(c.icon, size: 16),
              text: c.label,
            );
          }).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _kCats.map((c) => _InAppTab(cat: c, catCounts: _catCounts)).toList(),
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

String _fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso.length > 10 ? iso.substring(0, 10) : iso;
  return DateFormat('dd MMM yyyy, hh:mm a').format(dt.toLocal());
}

String _fmtAmount(dynamic amt) {
  final v = (amt as num?)?.toDouble() ?? 0;
  return '₹${v.toStringAsFixed(2)}';
}

class _StatChip {
  final String label;
  final String value;
  final Color color;
  const _StatChip(this.label, this.value, this.color);
}

Widget _summaryRow(BuildContext context, List<_StatChip> chips) {
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: chips
          .map((c) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.color.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.label,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppThemeColors.secondaryText(context))),
                      const SizedBox(height: 2),
                      Text(c.value,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: c.color)),
                    ],
                  ),
                ),
              ))
          .toList(),
    ),
  );
}

Widget _searchBar(
    BuildContext context, TextEditingController ctrl, VoidCallback onChanged) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: TextField(
      controller: ctrl,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        hintText: 'Search by name, email, or note…',
        hintStyle: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13),
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.cyan, size: 20),
        suffixIcon: ctrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: () {
                  ctrl.clear();
                  onChanged();
                },
                color: AppThemeColors.secondaryText(context),
              )
            : null,
        filled: true,
        fillColor: AppThemeColors.cardBg(context),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    ),
  );
}

Widget _userRow(BuildContext context, Map<String, dynamic> user, {VoidCallback? onTap}) {
  final name = (user['name'] ?? '').toString();
  final email = (user['email'] ?? '').toString();
  final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
  return GestureDetector(
    onTap: onTap,
    child: Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
          child: Text(initials,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.cyan)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppThemeColors.primaryText(context))),
              if (email.isNotEmpty)
                Text(email,
                    style: TextStyle(
                        fontSize: 11, color: AppThemeColors.mutedText(context))),
            ],
          ),
        ),
        if (onTap != null)
          Icon(Icons.chevron_right_rounded,
              size: 16, color: AppThemeColors.mutedText(context)),
      ],
    ),
  );
}

Widget _detailRow(BuildContext context, String label, String value,
    {Color? valueColor}) {
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5, color: AppThemeColors.secondaryText(context))),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? AppThemeColors.primaryText(context))),
        ),
      ],
    ),
  );
}

// ── Single tab for one category ───────────────────────────────────────────────

class _InAppTab extends StatefulWidget {
  final _Cat cat;
  final Map<String, int> catCounts;
  const _InAppTab({required this.cat, required this.catCounts});

  @override
  State<_InAppTab> createState() => _InAppTabState();
}

class _InAppTabState extends State<_InAppTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<dynamic> _txns = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  bool _isCoinLedger = false;
  bool _isQuickLedger = false;
  bool _flaggedOnly = false;
  String? _statusFilter;          // null | 'failed' | 'reversed'
  String _quickClearedFilter = 'all'; // 'all' | 'cleared' | 'pending'
  final _searchCtrl = TextEditingController();
  final _minAmountCtrl = TextEditingController();
  final _maxAmountCtrl = TextEditingController();
  String _search = '';
  Map<String, dynamic> _globalStats = {};
  Map<String, dynamic> _catStats = {};
  int _total = 0;
  DateTime? _fromDate;
  DateTime? _toDate;

  // Volume chart
  List<Map<String, dynamic>> _volumeData = [];
  bool _showChart = false;
  bool _chartLoading = false;
  bool _volumeIsCoin = false;

  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _minAmountCtrl.dispose();
    _maxAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool append = false}) async {
    if (append) {
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _txns = [];
        _hasMore = false;
      });
    }
    try {
      final skip = append ? _txns.length : 0;
      final buf = StringBuffer(
          '/api/admin/in-app-transactions?category=${widget.cat.key}&limit=$_pageSize&skip=$skip');
      if (_search.isNotEmpty) buf.write('&search=${Uri.encodeComponent(_search)}');
      if (_fromDate != null) buf.write('&startDate=${DateFormat('yyyy-MM-dd').format(_fromDate!)}');
      if (_toDate != null) buf.write('&endDate=${DateFormat('yyyy-MM-dd').format(_toDate!)}');
      if (_flaggedOnly) buf.write('&flagged=true');
      if (_minAmountCtrl.text.trim().isNotEmpty) buf.write('&minAmount=${Uri.encodeComponent(_minAmountCtrl.text.trim())}');
      if (_maxAmountCtrl.text.trim().isNotEmpty) buf.write('&maxAmount=${Uri.encodeComponent(_maxAmountCtrl.text.trim())}');
      if (_statusFilter != null) buf.write('&status=${Uri.encodeComponent(_statusFilter!)}');
      if (widget.cat.key == 'quick' && _quickClearedFilter != 'all') {
        buf.write('&cleared=${_quickClearedFilter == 'cleared' ? 'true' : 'false'}');
      }

      final res = await ApiClient.get(buf.toString());
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final newItems = (data['transactions'] ?? []) as List<dynamic>;
        setState(() {
          if (append) {
            _txns = [..._txns, ...newItems];
          } else {
            _txns = newItems;
            _globalStats = data['stats'] as Map<String, dynamic>? ?? {};
            _catStats = data['categoryStats'] as Map<String, dynamic>? ?? {};
            _isCoinLedger = data['isCoinLedger'] == true;
            _isQuickLedger = data['isQuickLedger'] == true;
          }
          _total = (data['total'] as num?)?.toInt() ?? 0;
          _hasMore = _txns.length < _total;
          _loading = false;
          _loadingMore = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load.';
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Network error.';
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _fetchVolume() async {
    if (_chartLoading) return;
    setState(() {
      _chartLoading = true;
      _showChart = true;
    });
    try {
      final res = await ApiClient.get(
          '/api/admin/in-app-transactions/volume?category=${widget.cat.key}&days=7');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _volumeData = ((data['days'] ?? []) as List).cast<Map<String, dynamic>>();
          _volumeIsCoin = data['coinLedger'] == true;
          _chartLoading = false;
        });
      } else {
        setState(() => _chartLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _chartLoading = false);
    }
  }

  Future<void> _exportCsv(BuildContext ctx) async {
    final messenger = ScaffoldMessenger.of(ctx);
    messenger.showSnackBar(
        const SnackBar(content: Text('Generating export…'), duration: Duration(seconds: 2)));
    try {
      final buf = StringBuffer(
          '/api/admin/in-app-transactions/export?category=${widget.cat.key}');
      if (_search.isNotEmpty) buf.write('&search=${Uri.encodeComponent(_search)}');
      if (_fromDate != null) buf.write('&startDate=${DateFormat('yyyy-MM-dd').format(_fromDate!)}');
      if (_toDate != null) buf.write('&endDate=${DateFormat('yyyy-MM-dd').format(_toDate!)}');
      if (_flaggedOnly) buf.write('&flagged=true');
      if (_minAmountCtrl.text.trim().isNotEmpty) buf.write('&minAmount=${Uri.encodeComponent(_minAmountCtrl.text.trim())}');
      if (_maxAmountCtrl.text.trim().isNotEmpty) buf.write('&maxAmount=${Uri.encodeComponent(_maxAmountCtrl.text.trim())}');
      if (_statusFilter != null) buf.write('&status=${Uri.encodeComponent(_statusFilter!)}');
      if (widget.cat.key == 'quick' && _quickClearedFilter != 'all') {
        buf.write('&cleared=${_quickClearedFilter == 'cleared' ? 'true' : 'false'}');
      }

      final res = await ApiClient.get(buf.toString());
      if (!mounted) return;
      if (res.statusCode != 200) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Export failed.'), backgroundColor: Colors.red));
        return;
      }
      final dir = await getTemporaryDirectory();
      final fname =
          'lenden_${widget.cat.key}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
      final file = File('${dir.path}/$fname');
      await file.writeAsString(res.body);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'LenDen In-App Transactions — ${widget.cat.label}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _toggleFlag(String id, bool current) async {
    try {
      final res = await ApiClient.post('/api/admin/in-app-transactions/$id/flag', body: {});
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          for (int i = 0; i < _txns.length; i++) {
            final tx = _txns[i] as Map<String, dynamic>;
            if (tx['_id'].toString() == id) {
              _txns[i] = Map<String, dynamic>.from(tx)..['adminFlagged'] = !current;
              break;
            }
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme:
                Theme.of(ctx).colorScheme.copyWith(primary: AppColors.cyan)),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) _fromDate = picked; else _toDate = picked;
    });
    _fetch();
  }

  void _setPreset(String preset) {
    final now = DateTime.now();
    DateTime from;
    switch (preset) {
      case 'today':
        from = DateTime(now.year, now.month, now.day);
      case 'week':
        from = now.subtract(const Duration(days: 6));
      case 'month':
      default:
        from = DateTime(now.year, now.month, 1);
    }
    setState(() {
      _fromDate = from;
      _toDate = now;
    });
    _fetch();
  }

  bool _isPresetActive(String preset) {
    if (_fromDate == null) return false;
    final now = DateTime.now();
    switch (preset) {
      case 'today':
        return _fromDate!.year == now.year &&
            _fromDate!.month == now.month &&
            _fromDate!.day == now.day;
      case 'week':
        final wStart = now.subtract(const Duration(days: 6));
        return _fromDate!.year == wStart.year &&
            _fromDate!.month == wStart.month &&
            _fromDate!.day == wStart.day;
      case 'month':
        return _fromDate!.year == now.year &&
            _fromDate!.month == now.month &&
            _fromDate!.day == 1;
      default:
        return false;
    }
  }

  void _clearFilters() {
    _searchCtrl.clear();
    _minAmountCtrl.clear();
    _maxAmountCtrl.clear();
    setState(() {
      _search = '';
      _fromDate = null;
      _toDate = null;
      _flaggedOnly = false;
      _statusFilter = null;
      _quickClearedFilter = 'all';
    });
    _fetch();
  }

  double get _totalDebit =>
      (_globalStats['debit']?['total'] as num?)?.toDouble() ?? 0;
  double get _totalCredit =>
      (_globalStats['credit']?['total'] as num?)?.toDouble() ?? 0;
  int get _totalEarned =>
      (_globalStats['earned']?['total'] as num?)?.toInt() ?? 0;
  int get _totalSpent =>
      (_globalStats['spent']?['total'] as num?)?.toInt() ?? 0;
  double get _catTotal => (_catStats['total'] as num?)?.toDouble() ?? 0;
  int get _catCount => (_catStats['count'] as num?)?.toInt() ?? 0;
  int get _catCleared => (_catStats['cleared'] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isAll = widget.cat.key == 'all';
    final accentColor = widget.cat.color;
    final hasFilters = _fromDate != null ||
        _toDate != null ||
        _search.isNotEmpty ||
        _flaggedOnly ||
        _minAmountCtrl.text.isNotEmpty ||
        _maxAmountCtrl.text.isNotEmpty ||
        _statusFilter != null ||
        _quickClearedFilter != 'all';

    List<_StatChip> chips;
    if (_isCoinLedger) {
      chips = [
        _StatChip('Total Earned', '$_totalEarned coins', Colors.green),
        _StatChip('Total Spent', '$_totalSpent coins', Colors.red),
        _StatChip('Loaded', _txns.length.toString(), AppColors.cyan),
      ];
    } else if (_isQuickLedger) {
      chips = [
        _StatChip('Total', _catCount.toString(), accentColor),
        _StatChip('Cleared', _catCleared.toString(), Colors.green),
        _StatChip('Pending', (_catCount - _catCleared).toString(), Colors.orange),
      ];
    } else if (isAll) {
      chips = [
        _StatChip('Total Debits', _fmtAmount(_totalDebit), Colors.red),
        _StatChip('Total Credits', _fmtAmount(_totalCredit), Colors.green),
        _StatChip('Loaded', _txns.length.toString(), AppColors.cyan),
      ];
    } else {
      chips = [
        _StatChip('${widget.cat.label} Count', _catCount.toString(), accentColor),
        _StatChip('Volume', _fmtAmount(_catTotal), accentColor),
        _StatChip('Showing', _txns.length.toString(), AppColors.cyan),
      ];
    }

    return RefreshIndicator(
      onRefresh: () => _fetch(),
      color: AppColors.cyan,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow(context, chips),

                // Per-category breakdown — All tab only
                if (isAll && widget.catCounts.isNotEmpty)
                  _categoryBreakdownBar(context),

                // Controls: chart toggle + export
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Row(
                    children: [
                      _controlChip(
                        context,
                        icon: Icons.bar_chart_rounded,
                        label: '7-Day Trend',
                        active: _showChart,
                        onTap: () {
                          if (_showChart) {
                            setState(() => _showChart = false);
                          } else {
                            _fetchVolume();
                          }
                        },
                      ),
                      const Spacer(),
                      Builder(
                        builder: (ctx) => _controlChip(
                          context,
                          icon: Icons.download_rounded,
                          label: 'Export CSV',
                          active: false,
                          activeColor: Colors.green,
                          onTap: () => _exportCsv(ctx),
                        ),
                      ),
                    ],
                  ),
                ),

                // Volume chart
                if (_showChart)
                  _VolumeBar(
                    data: _volumeData,
                    loading: _chartLoading,
                    color: accentColor,
                    isCoin: _volumeIsCoin,
                  ),

                // Search
                _searchBar(context, _searchCtrl, () {
                  setState(() => _search = _searchCtrl.text);
                  Future.delayed(const Duration(milliseconds: 600), _fetch);
                }),

                // Date preset chips
                _datePresetsRow(context),

                // Date filter row
                _dateFilterRow(context, hasFilters),

                // Amount range filter (not for coin-ledger tabs)
                if (!_isCoinLedger)
                  _amountRangeRow(context),

                // Filter chips row
                if (!_isCoinLedger)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Row(
                      children: [
                        if (_isQuickLedger) ...[
                          _filterChip(context, 'Cleared', _quickClearedFilter == 'cleared',
                              Colors.green, () {
                            setState(() => _quickClearedFilter =
                                _quickClearedFilter == 'cleared' ? 'all' : 'cleared');
                            _fetch();
                          }),
                          const SizedBox(width: 8),
                          _filterChip(context, 'Pending', _quickClearedFilter == 'pending',
                              Colors.orange, () {
                            setState(() => _quickClearedFilter =
                                _quickClearedFilter == 'pending' ? 'all' : 'pending');
                            _fetch();
                          }),
                        ] else ...[
                          _filterChip(context, 'Flagged', _flaggedOnly, Colors.red, () {
                            setState(() => _flaggedOnly = !_flaggedOnly);
                            _fetch();
                          }),
                          const SizedBox(width: 8),
                          _filterChip(context, 'Failed', _statusFilter == 'failed',
                              Colors.orange.shade800, () {
                            setState(() => _statusFilter =
                                _statusFilter == 'failed' ? null : 'failed');
                            _fetch();
                          }),
                          const SizedBox(width: 8),
                          _filterChip(context, 'Reversed', _statusFilter == 'reversed',
                              Colors.purple, () {
                            setState(() => _statusFilter =
                                _statusFilter == 'reversed' ? null : 'reversed');
                            _fetch();
                          }),
                        ],
                        const Spacer(),
                        Text('$_total total',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppThemeColors.mutedText(context))),
                      ],
                    ),
                  ),

                const SizedBox(height: 6),
              ],
            ),
          ),

          if (_loading)
            const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: AppColors.cyan)))
          else if (_error != null)
            SliverFillRemaining(
                child: Center(
                    child: Text(_error!, style: const TextStyle(color: Colors.red))))
          else if (_txns.isEmpty)
            SliverFillRemaining(
                child: Center(
                    child: Text(
                        'No ${widget.cat.label.toLowerCase()} records found.')))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    if (i < _txns.length) {
                      final item = _txns[i] as Map<String, dynamic>;
                      return _isQuickLedger
                          ? _quickTxCard(ctx, item)
                          : _isCoinLedger
                              ? _coinLedgerCard(ctx, item)
                              : _txnCard(ctx, item);
                    }
                    if (_loadingMore) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                            child: CircularProgressIndicator(color: AppColors.cyan)),
                      );
                    }
                    if (_hasMore) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: TextButton.icon(
                            onPressed: () => _fetch(append: true),
                            icon: const Icon(Icons.expand_more,
                                size: 18, color: AppColors.cyan),
                            label: Text(
                              'Load More (${_total - _txns.length} remaining)',
                              style: const TextStyle(
                                  color: AppColors.cyan,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text(
                          'All $_total records loaded',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppThemeColors.mutedText(context)),
                        ),
                      ),
                    );
                  },
                  childCount: _txns.length + 1,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _controlChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool active,
    Color activeColor = AppColors.cyan,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.15)
              : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active
                  ? activeColor
                  : AppThemeColors.divider(context)),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 14,
                color: active ? activeColor : AppThemeColors.secondaryText(context)),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: active
                        ? activeColor
                        : AppThemeColors.secondaryText(context))),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(BuildContext context, String label, bool selected, Color color,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : AppThemeColors.divider(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.check_rounded, size: 11, color: color),
              ),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    color: selected ? color : AppThemeColors.secondaryText(context),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Widget _amountRangeRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Expanded(child: _amountField(context, _minAmountCtrl, 'Min ₹')),
          const SizedBox(width: 8),
          Expanded(child: _amountField(context, _maxAmountCtrl, 'Max ₹')),
        ],
      ),
    );
  }

  Widget _amountField(BuildContext context, TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) {
        setState(() {});
        Future.delayed(const Duration(milliseconds: 700), _fetch);
      },
      style: TextStyle(fontSize: 13, color: AppThemeColors.primaryText(context)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 12),
        filled: true,
        fillColor: AppThemeColors.cardBg(context),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        suffixIcon: ctrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 14),
                onPressed: () {
                  ctrl.clear();
                  setState(() {});
                  _fetch();
                },
                color: AppThemeColors.mutedText(context),
                padding: EdgeInsets.zero,
              )
            : null,
      ),
    );
  }

  Widget _categoryBreakdownBar(BuildContext context) {
    final cats = _kCats
        .where((c) => c.key != 'all' && c.key != 'rewards' && c.key != 'refunds')
        .toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: cats.map((c) {
          final cnt = widget.catCounts[c.key] ?? 0;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.color.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(c.icon, size: 12, color: c.color),
                  const SizedBox(width: 4),
                  Text('${c.label}: $cnt',
                      style: TextStyle(
                          fontSize: 11,
                          color: c.color,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _datePresetsRow(BuildContext context) {
    final presets = [('Today', 'today'), ('This Week', 'week'), ('This Month', 'month')];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: presets.map((p) {
          final active = _isPresetActive(p.$2);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _setPreset(p.$2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.cyan.withValues(alpha: 0.15)
                      : AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: active
                          ? AppColors.cyan
                          : AppThemeColors.divider(context)),
                ),
                child: Text(p.$1,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: active ? FontWeight.bold : FontWeight.normal,
                        color: active
                            ? AppColors.cyan
                            : AppThemeColors.secondaryText(context))),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _dateFilterRow(BuildContext context, bool hasFilt) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _pickDate(true),
              child: _dateChip(context, _fromDate, 'From Date'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => _pickDate(false),
              child: _dateChip(context, _toDate, 'To Date'),
            ),
          ),
          if (hasFilt) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _clearFilters,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.clear_rounded, size: 16, color: Colors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dateChip(BuildContext context, DateTime? date, String placeholder) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: date != null ? AppColors.cyan : AppThemeColors.divider(context)),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today_rounded,
              size: 13,
              color: date != null ? AppColors.cyan : AppThemeColors.mutedText(context)),
          const SizedBox(width: 6),
          Text(
            date != null ? DateFormat('dd MMM').format(date) : placeholder,
            style: TextStyle(
                fontSize: 12,
                color: date != null
                    ? AppColors.cyan
                    : AppThemeColors.secondaryText(context)),
          ),
        ],
      ),
    );
  }

  Widget _txnCard(BuildContext context, Map<String, dynamic> tx) {
    final user = (tx['user'] is Map)
        ? tx['user'] as Map<String, dynamic>
        : <String, dynamic>{};
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final type = (tx['type'] ?? '').toString();
    final note = (tx['note'] ?? '').toString();
    final fromEmail = (tx['fromEmail'] ?? '').toString();
    final toEmail = (tx['toEmail'] ?? '').toString();
    final date = (tx['createdAt'] ?? '').toString();
    final id = (tx['_id'] ?? '').toString();
    final flagged = tx['adminFlagged'] == true;

    final isDebit = type == 'debit';
    final amtColor = isDebit ? Colors.red : Colors.green;
    final amtPrefix = isDebit ? '−' : '+';
    final cat = _detectCat(tx);

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('ID copied: ${id.length > 16 ? '${id.substring(0, 16)}…' : id}'),
              duration: const Duration(seconds: 2)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: flagged
                  ? Colors.red.withValues(alpha: 0.45)
                  : AppThemeColors.divider(context),
              width: flagged ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cat.color.withValues(alpha: 0.10), Colors.transparent],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  Icon(cat.icon, size: 15, color: cat.color),
                  const SizedBox(width: 7),
                  Text(cat.label.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: cat.color,
                          letterSpacing: 1)),
                  const Spacer(),
                  // Flag button
                  GestureDetector(
                    onTap: () => _toggleFlag(id, flagged),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(
                        flagged ? Icons.flag_rounded : Icons.flag_outlined,
                        size: 17,
                        color: flagged ? Colors.red : AppThemeColors.mutedText(context),
                      ),
                    ),
                  ),
                  Text('$amtPrefix${_fmtAmount(amount)}',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: amtColor)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _userRow(context, user,
                      onTap: user.isNotEmpty
                          ? () => _showUserDrilldown(context, user, tx)
                          : null),
                  const SizedBox(height: 10),
                  if (fromEmail.isNotEmpty)
                    _detailRow(context, 'From', fromEmail,
                        valueColor: const Color(0xFF1E88E5)),
                  if (toEmail.isNotEmpty)
                    _detailRow(context, 'To', toEmail,
                        valueColor: const Color(0xFF43A047)),
                  if (note.isNotEmpty) _detailRow(context, 'Note', note),
                  _detailRow(context, 'Type', type, valueColor: amtColor),
                  _detailRow(context, 'Date', _fmtDate(date)),
                  if (flagged)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.flag_rounded, size: 11, color: Colors.red),
                          const SizedBox(width: 4),
                          const Text('Flagged by admin',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickTxCard(BuildContext context, Map<String, dynamic> qt) {
    final id = (qt['_id'] ?? '').toString();
    final amount = (qt['amount'] as num?)?.toDouble() ?? 0;
    final currency = (qt['currency'] ?? 'INR').toString();
    final description = (qt['description'] ?? '').toString();
    final role = (qt['role'] ?? '').toString();
    final cleared = qt['cleared'] == true;
    final settleStatus = (qt['settlementStatus'] ?? 'none').toString();
    final paymentMethod = (qt['paymentMethod'] ?? '').toString();
    final date = (qt['createdAt'] ?? '').toString();
    final category = (qt['category'] ?? '').toString();

    final usersPopulated = (qt['usersPopulated'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final creatorEmail = (qt['creatorEmail'] ?? '').toString().toLowerCase();
    final creator = usersPopulated.firstWhere(
      (u) => (u['email'] ?? '').toString().toLowerCase() == creatorEmail,
      orElse: () => usersPopulated.isNotEmpty ? usersPopulated.first : <String, dynamic>{},
    );
    final counterparty = usersPopulated.firstWhere(
      (u) => (u['email'] ?? '').toString().toLowerCase() != creatorEmail,
      orElse: () => usersPopulated.length > 1 ? usersPopulated.last : <String, dynamic>{},
    );

    final cat = _kCats.firstWhere((c) => c.key == 'quick');
    final statusColor = cleared ? Colors.green : Colors.orange;
    final statusLabel = cleared ? 'Cleared' : 'Pending';

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('ID copied: ${id.length > 16 ? '${id.substring(0, 16)}…' : id}'),
              duration: const Duration(seconds: 2)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: cleared
                  ? Colors.green.withValues(alpha: 0.3)
                  : AppThemeColors.divider(context)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cat.color.withValues(alpha: 0.10), Colors.transparent],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  Icon(cat.icon, size: 15, color: cat.color),
                  const SizedBox(width: 7),
                  Text(
                    category.isNotEmpty && category != 'other'
                        ? category.toUpperCase()
                        : 'QUICK TX',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: cat.color,
                        letterSpacing: 1),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(statusLabel,
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: statusColor)),
                  ),
                  const Spacer(),
                  Text(
                    '${currency.toUpperCase()} ${amount.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold, color: cat.color),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Creator row
                  if (creator.isNotEmpty) ...[
                    _userRow(context, creator,
                        onTap: (creator['_id'] ?? '').toString().isNotEmpty
                            ? () => _showUserDrilldown(context, creator, {'user': creator, '_id': null})
                            : null),
                    const SizedBox(height: 4),
                  ],
                  // Role
                  if (role.isNotEmpty)
                    _detailRow(context, 'Role', role[0].toUpperCase() + role.substring(1),
                        valueColor: role == 'lender' ? Colors.green : Colors.blue),
                  // Counterparty
                  if (counterparty.isNotEmpty)
                    _detailRow(context, 'Counterparty',
                        (counterparty['name'] ?? counterparty['email'] ?? '').toString(),
                        valueColor: AppColors.cyan),
                  if (description.isNotEmpty) _detailRow(context, 'Description', description),
                  _detailRow(context, 'Settlement', settleStatus,
                      valueColor: settleStatus == 'accepted'
                          ? Colors.green
                          : settleStatus == 'rejected'
                              ? Colors.red
                              : AppThemeColors.secondaryText(context)),
                  if (paymentMethod.isNotEmpty)
                    _detailRow(context, 'Paid via', paymentMethod),
                  _detailRow(context, 'Date', _fmtDate(date)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coinLedgerCard(BuildContext context, Map<String, dynamic> entry) {
    final user = (entry['user'] is Map)
        ? entry['user'] as Map<String, dynamic>
        : <String, dynamic>{};
    final coins = (entry['coins'] as num?)?.toInt() ?? 0;
    final direction = (entry['direction'] ?? '').toString();
    final source = (entry['source'] ?? '').toString();
    final title = (entry['title'] ?? '').toString();
    final description = (entry['description'] ?? '').toString();
    final date = (entry['occurredAt'] ?? entry['createdAt'] ?? '').toString();
    final id = (entry['_id'] ?? '').toString();

    final isEarned = direction == 'earned';
    final accentColor = isEarned ? Colors.green : Colors.orange;
    final prefix = isEarned ? '+' : '−';
    final rewardCat = _kCats.firstWhere((c) => c.key == 'rewards');
    final sourceLabel = source
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('ID copied: ${id.length > 16 ? '${id.substring(0, 16)}…' : id}'),
              duration: const Duration(seconds: 2)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppThemeColors.divider(context)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    rewardCat.color.withValues(alpha: 0.10),
                    Colors.transparent
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  Icon(rewardCat.icon, size: 15, color: rewardCat.color),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      title.isNotEmpty ? title.toUpperCase() : 'COIN REWARD',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: rewardCat.color,
                          letterSpacing: 1),
                    ),
                  ),
                  Text('$prefix$coins coins',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold, color: accentColor)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _userRow(context, user,
                      onTap: user.isNotEmpty
                          ? () => _showUserDrilldown(context, user, entry)
                          : null),
                  const SizedBox(height: 10),
                  if (sourceLabel.isNotEmpty)
                    _detailRow(context, 'Source', sourceLabel,
                        valueColor: rewardCat.color),
                  if (description.isNotEmpty)
                    _detailRow(context, 'Details', description),
                  _detailRow(context, 'Direction', isEarned ? 'Earned' : 'Spent',
                      valueColor: accentColor),
                  _detailRow(context, 'Date', _fmtDate(date)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _Cat _detectCat(Map<String, dynamic> tx) {
    final st = (tx['sourceType'] ?? '').toString();
    const stMap = {
      'p2p': 'p2p',
      'qr_internal': 'qr',
      'qr_external': 'qr',
      'quick': 'quick',
      'secure': 'secure',
      'group': 'group',
      'subscription': 'subscription',
      'coins': 'coins',
    };
    if (stMap.containsKey(st)) {
      return _kCats.firstWhere((c) => c.key == stMap[st]!);
    }
    final note = (tx['note'] ?? '').toString().toLowerCase();
    final hasScan = tx['scanPaymentRequestId'] != null &&
        tx['scanPaymentRequestId'].toString().isNotEmpty &&
        tx['scanPaymentRequestId'].toString() != 'null';
    if (note.contains('quick transaction')) return _kCats.firstWhere((c) => c.key == 'quick');
    if (note.contains('secure transaction')) return _kCats.firstWhere((c) => c.key == 'secure');
    if (note.contains('group expense')) return _kCats.firstWhere((c) => c.key == 'group');
    if (note.contains('qr payment') || hasScan) return _kCats.firstWhere((c) => c.key == 'qr');
    if (note.contains('subscription')) return _kCats.firstWhere((c) => c.key == 'subscription');
    if (note.contains('lenden coin') ||
        (note.contains('bought') && note.contains('coin'))) {
      return _kCats.firstWhere((c) => c.key == 'coins');
    }
    if (note.contains('refund') || note.contains('reversed')) {
      return _kCats.firstWhere((c) => c.key == 'refunds');
    }
    if (note.contains('wallet transfer')) return _kCats.firstWhere((c) => c.key == 'p2p');
    if (widget.cat.key != 'all') return widget.cat;
    return _kCats.first;
  }

  void _showUserDrilldown(
      BuildContext context, Map<String, dynamic> user, Map<String, dynamic> tx) {
    final rawUser = tx['user'];
    final userId =
        (rawUser is Map) ? (rawUser['_id'] ?? '').toString() : '';
    if (userId.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserDrilldownSheet(userId: userId, user: user),
    );
  }
}

// ── Volume bar chart (custom, no fl_chart dependency) ─────────────────────────

class _VolumeBar extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool loading;
  final Color color;
  final bool isCoin;
  const _VolumeBar(
      {required this.data,
      required this.loading,
      required this.color,
      this.isCoin = false});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator(color: AppColors.cyan)));
    }
    if (data.isEmpty) {
      return SizedBox(
          height: 60,
          child: Center(
              child: Text('No data for this period',
                  style: TextStyle(
                      fontSize: 12, color: AppThemeColors.mutedText(context)))));
    }

    final counts = data.map((d) => (d['count'] as num?)?.toDouble() ?? 0).toList();
    final amounts = data.map((d) => (d['amount'] as num?)?.toDouble() ?? 0).toList();
    final maxCount = counts.reduce((a, b) => a > b ? a : b);
    final maxAmount = amounts.reduce((a, b) => a > b ? a : b);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppThemeColors.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('7-Day Activity',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.secondaryText(context))),
          const SizedBox(height: 10),
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(data.length, (i) {
                final d = data[i];
                final count = counts[i];
                final barH = maxCount > 0 ? (count / maxCount * 60).clamp(4.0, 60.0) : 4.0;
                final dateStr = (d['date'] ?? '').toString();
                final dt = DateTime.tryParse(dateStr);
                final label = dt != null
                    ? DateFormat('d/M').format(dt)
                    : (dateStr.length >= 5 ? dateStr.substring(5) : dateStr);

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (count > 0)
                          Text(count.toInt().toString(),
                              style: TextStyle(
                                  fontSize: 8,
                                  color: color,
                                  fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Tooltip(
                          message: isCoin
                              ? '${count.toInt()} entries\n${amounts[i].toInt()} coins'
                              : '${count.toInt()} txns\n₹${amounts[i].toStringAsFixed(0)}',
                          child: Container(
                            height: barH,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(label,
                            style: TextStyle(
                                fontSize: 9,
                                color: AppThemeColors.mutedText(context))),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Peak: ${maxCount.toInt()} entries',
                  style: TextStyle(
                      fontSize: 10, color: AppThemeColors.mutedText(context))),
              Text(
                isCoin
                    ? 'Peak: ${maxAmount.toInt()} coins'
                    : 'Peak vol: ₹${maxAmount.toStringAsFixed(0)}',
                style: TextStyle(
                    fontSize: 10, color: AppThemeColors.mutedText(context)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── User drill-down bottom sheet ──────────────────────────────────────────────

class _UserDrilldownSheet extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> user;
  const _UserDrilldownSheet({required this.userId, required this.user});

  @override
  State<_UserDrilldownSheet> createState() => _UserDrilldownSheetState();
}

class _UserDrilldownSheetState extends State<_UserDrilldownSheet> {
  List<dynamic> _txns = [];
  bool _loading = true;
  String? _error;
  bool _hasMore = false;
  int _total = 0;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch({bool append = false}) async {
    if (!append) setState(() { _loading = true; _error = null; _txns = []; });
    try {
      final skip = append ? _txns.length : 0;
      final res = await ApiClient.get(
          '/api/admin/in-app-transactions?category=all&userId=${widget.userId}&limit=$_pageSize&skip=$skip');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final newItems = (data['transactions'] ?? []) as List<dynamic>;
        setState(() {
          _txns = append ? [..._txns, ...newItems] : newItems;
          _total = (data['total'] as num?)?.toInt() ?? 0;
          _hasMore = _txns.length < _total;
          _loading = false;
        });
      } else {
        setState(() { _error = 'Failed to load.'; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = 'Network error.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.user['name'] ?? '').toString();
    final email = (widget.user['email'] ?? '').toString();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: AppThemeColors.scaffoldBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppThemeColors.divider(context),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.cyan),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppThemeColors.primaryText(context))),
                        if (email.isNotEmpty)
                          Text(email,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppThemeColors.mutedText(context))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$_total txns',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.cyan,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppThemeColors.divider(context)),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.cyan))
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.red)))
                      : _txns.isEmpty
                          ? Center(
                              child: Text('No in-app transactions found.',
                                  style: TextStyle(
                                      color: AppThemeColors.secondaryText(context))))
                          : ListView.builder(
                              controller: ctrl,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _txns.length + (_hasMore ? 1 : 0),
                              itemBuilder: (ctx, i) {
                                if (i < _txns.length) {
                                  return _miniCard(
                                      ctx, _txns[i] as Map<String, dynamic>);
                                }
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Center(
                                    child: TextButton.icon(
                                      onPressed: () => _fetch(append: true),
                                      icon: const Icon(Icons.expand_more,
                                          size: 18, color: AppColors.cyan),
                                      label: Text(
                                          'Load More (${_total - _txns.length} left)',
                                          style: const TextStyle(
                                              color: AppColors.cyan)),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniCard(BuildContext context, Map<String, dynamic> tx) {
    final type = (tx['type'] ?? '').toString();
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final note = (tx['note'] ?? '').toString();
    final date = (tx['createdAt'] ?? '').toString();
    final isDebit = type == 'debit';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppThemeColors.divider(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (isDebit ? Colors.red : Colors.green).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isDebit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 18,
              color: isDebit ? Colors.red : Colors.green,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.isNotEmpty ? note : type,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppThemeColors.primaryText(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(_fmtDate(date),
                    style: TextStyle(
                        fontSize: 11, color: AppThemeColors.mutedText(context))),
              ],
            ),
          ),
          Text(
            '${isDebit ? '−' : '+'}${_fmtAmount(amount)}',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDebit ? Colors.red : Colors.green),
          ),
        ],
      ),
    );
  }
}
