import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../widgets/app_colors.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';

class AdminRealPaymentsPage extends StatefulWidget {
  const AdminRealPaymentsPage({super.key});

  @override
  State<AdminRealPaymentsPage> createState() => _AdminRealPaymentsPageState();
}

class _AdminRealPaymentsPageState extends State<AdminRealPaymentsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        title: Text('Real Payments',
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
          tabs: const [
            Tab(icon: Icon(Icons.add_card_rounded, size: 18), text: 'Add Money'),
            Tab(icon: Icon(Icons.account_balance_rounded, size: 18), text: 'Withdrawals'),
            Tab(icon: Icon(Icons.card_membership_rounded, size: 18), text: 'Subscriptions'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _TopUpsTab(),
          _WithdrawalsTab(),
          _SubscriptionsTab(),
        ],
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

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

Widget _statusBadge(String status) {
  Color c;
  switch (status.toLowerCase()) {
    case 'processed':
    case 'active':
      c = Colors.green;
      break;
    case 'processing':
      c = Colors.orange;
      break;
    case 'failed':
    case 'expired':
      c = Colors.red;
      break;
    case 'reversed':
      c = Colors.purple;
      break;
    default:
      c = Colors.grey;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
    child: Text(status,
        style:
            TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
  );
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

class _StatChip {
  final String label;
  final String value;
  final Color color;
  const _StatChip(this.label, this.value, this.color);
}

Widget _searchBar(BuildContext context, TextEditingController ctrl,
    VoidCallback onChanged) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: TextField(
      controller: ctrl,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        hintText: 'Search by name or email…',
        hintStyle:
            TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13),
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
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
    ),
  );
}

Widget _userRow(BuildContext context, Map<String, dynamic> user) {
  final name = (user['name'] ?? '').toString();
  final email = (user['email'] ?? '').toString();
  final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
  return Row(
    children: [
      CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
        child: Text(initials,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.cyan)),
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
                      fontSize: 11,
                      color: AppThemeColors.mutedText(context))),
          ],
        ),
      ),
    ],
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
          width: 110,
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  color: AppThemeColors.secondaryText(context))),
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

// ── Tab 1: Add Money (Wallet Top-Ups) ─────────────────────────────────────────

class _TopUpsTab extends StatefulWidget {
  const _TopUpsTab();

  @override
  State<_TopUpsTab> createState() => _TopUpsTabState();
}

class _TopUpsTabState extends State<_TopUpsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<dynamic> _topups = [];
  bool _loading = true;
  String? _error;
  bool _showAll = false;
  final _searchCtrl = TextEditingController();
  String _search = '';
  Map<String, dynamic> _stats = {};
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final params = StringBuffer('/api/admin/real-payments/topups?limit=100');
      if (_search.isNotEmpty) params.write('&search=${Uri.encodeComponent(_search)}');
      if (_fromDate != null) params.write('&startDate=${DateFormat('yyyy-MM-dd').format(_fromDate!)}');
      if (_toDate != null) params.write('&endDate=${DateFormat('yyyy-MM-dd').format(_toDate!)}');
      final res = await ApiClient.get(params.toString());
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _topups = data['topups'] ?? [];
          _stats = data['stats'] ?? {};
          _loading = false;
        });
      } else {
        setState(() { _error = 'Failed to load top-ups.'; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = 'Network error.'; _loading = false; });
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppColors.cyan)),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) _fromDate = picked; else _toDate = picked;
    });
    _fetch();
  }

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() { _search = ''; _fromDate = null; _toDate = null; _showAll = false; });
    _fetch();
  }

  List<dynamic> get _displayed => _showAll ? _topups : _topups.take(3).toList();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final totalAmt = (_stats['totalAmount'] as num?)?.toDouble() ?? 0;
    final count = (_stats['count'] as num?)?.toInt() ?? 0;

    return RefreshIndicator(
      onRefresh: _fetch,
      color: AppColors.cyan,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                _summaryRow(context, [
                  _StatChip('Total Top-ups', count.toString(), AppColors.cyan),
                  _StatChip('Total Amount', _fmtAmount(totalAmt), Colors.green),
                  _StatChip('Showing', _topups.length.toString(), Colors.orange),
                ]),
                _searchBar(context, _searchCtrl, () {
                  setState(() => _search = _searchCtrl.text);
                  Future.delayed(const Duration(milliseconds: 600), _fetch);
                }),
                _dateFilterRow(context),
                const SizedBox(height: 4),
              ],
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: AppColors.cyan)))
          else if (_error != null)
            SliverFillRemaining(
                child: Center(child: Text(_error!, style: const TextStyle(color: Colors.red))))
          else if (_topups.isEmpty)
            const SliverFillRemaining(
                child: Center(child: Text('No wallet top-ups found.')))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    if (i == _displayed.length) {
                      return _viewAllButton(context, _topups.length);
                    }
                    return _topUpCard(ctx, _displayed[i] as Map<String, dynamic>);
                  },
                  childCount: _displayed.length + (_topups.length > 3 ? 1 : 0),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateFilterRow(BuildContext context) {
    final hasFilt = _fromDate != null || _toDate != null || _search.isNotEmpty;
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
          Icon(Icons.calendar_today_rounded, size: 13,
              color: date != null ? AppColors.cyan : AppThemeColors.mutedText(context)),
          const SizedBox(width: 6),
          Text(
            date != null ? DateFormat('dd MMM').format(date) : placeholder,
            style: TextStyle(
                fontSize: 12,
                color: date != null ? AppColors.cyan : AppThemeColors.secondaryText(context)),
          ),
        ],
      ),
    );
  }

  Widget _topUpCard(BuildContext context, Map<String, dynamic> t) {
    final user = (t['user'] is Map) ? t['user'] as Map<String, dynamic> : <String, dynamic>{};
    final amount = (t['amount'] as num?)?.toDouble() ?? 0;
    final payId = (t['razorpayPaymentId'] ?? '').toString();
    final date = (t['createdAt'] ?? '').toString();

    return Container(
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
          // Header with gradient accent
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.withValues(alpha: 0.08), Colors.transparent],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.add_card_rounded, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                const Text('WALLET TOP-UP',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                        letterSpacing: 1)),
                const Spacer(),
                Text(_fmtAmount(amount),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _userRow(context, user),
                const SizedBox(height: 10),
                _detailRow(context, 'Payment ID',
                    payId.isNotEmpty ? payId : '—',
                    valueColor: AppColors.cyan),
                _detailRow(context, 'Method', 'Razorpay Manual'),
                _detailRow(context, 'Date & Time', _fmtDate(date)),
                if ((t['note'] ?? '').toString().isNotEmpty)
                  _detailRow(context, 'Note', t['note'].toString()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewAllButton(BuildContext context, int total) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: TextButton.icon(
          onPressed: () => setState(() => _showAll = !_showAll),
          icon: Icon(_showAll ? Icons.expand_less : Icons.expand_more,
              size: 18, color: AppColors.cyan),
          label: Text(
            _showAll ? 'Show Less' : 'View All ($total)',
            style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// ── Tab 2: Withdrawals ─────────────────────────────────────────────────────────

class _WithdrawalsTab extends StatefulWidget {
  const _WithdrawalsTab();

  @override
  State<_WithdrawalsTab> createState() => _WithdrawalsTabState();
}

class _WithdrawalsTabState extends State<_WithdrawalsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<dynamic> _withdrawals = [];
  bool _loading = true;
  String? _error;
  bool _showAll = false;
  String _statusFilter = 'all';
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res =
          await ApiClient.get('/api/admin/withdrawals?status=$_statusFilter');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _withdrawals = data['withdrawals'] ?? [];
          _loading = false;
        });
      } else {
        setState(() { _error = 'Failed to load withdrawals.'; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = 'Network error.'; _loading = false; });
    }
  }

  List<dynamic> get _filtered {
    if (_search.isEmpty) return _withdrawals;
    final q = _search.toLowerCase();
    return _withdrawals.where((w) {
      final user = (w['user'] is Map) ? w['user'] as Map : {};
      final name = (user['name'] ?? '').toString().toLowerCase();
      final email = (user['email'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  List<dynamic> get _displayed =>
      _showAll ? _filtered : _filtered.take(3).toList();

  Map<String, double> get _stats {
    double total = 0, pending = 0, processed = 0;
    for (final w in _withdrawals) {
      final amt = ((w['amount'] as num?)?.toDouble() ?? 0);
      total += amt;
      if ((w['status'] ?? '') == 'processing') pending += amt;
      if ((w['status'] ?? '') == 'processed') processed += amt;
    }
    return {'total': total, 'pending': pending, 'processed': processed};
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = _stats;

    return RefreshIndicator(
      onRefresh: _fetch,
      color: AppColors.cyan,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                _summaryRow(context, [
                  _StatChip('Total Count', _withdrawals.length.toString(), AppColors.cyan),
                  _StatChip('Total Amount', _fmtAmount(s['total']), Colors.blue),
                  _StatChip('Pending', _fmtAmount(s['pending']), Colors.orange),
                  _StatChip('Processed', _fmtAmount(s['processed']), Colors.green),
                ]),
                _searchBar(context, _searchCtrl, () {
                  setState(() { _search = _searchCtrl.text; _showAll = false; });
                }),
                _filterChips(context),
                const SizedBox(height: 4),
              ],
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: AppColors.cyan)))
          else if (_error != null)
            SliverFillRemaining(
                child: Center(child: Text(_error!, style: const TextStyle(color: Colors.red))))
          else if (_filtered.isEmpty)
            const SliverFillRemaining(child: Center(child: Text('No withdrawals found.')))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    if (i == _displayed.length) {
                      return _viewAllBtn(context, _filtered.length);
                    }
                    return _wCard(ctx, _displayed[i] as Map<String, dynamic>);
                  },
                  childCount: _displayed.length + (_filtered.length > 3 ? 1 : 0),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChips(BuildContext context) {
    const opts = [
      {'v': 'all', 'l': 'All'},
      {'v': 'processing', 'l': 'Pending'},
      {'v': 'processed', 'l': 'Processed'},
      {'v': 'failed', 'l': 'Failed'},
      {'v': 'reversed', 'l': 'Reversed'},
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: opts.map((o) {
          final sel = _statusFilter == o['v'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() { _statusFilter = o['v']!; _showAll = false; });
                _fetch();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: sel ? AppColors.cyan : AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: sel ? AppColors.cyan : AppThemeColors.divider(context)),
                ),
                child: Text(o['l']!,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : AppThemeColors.secondaryText(context))),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _wCard(BuildContext context, Map<String, dynamic> w) {
    final user = (w['user'] is Map) ? w['user'] as Map<String, dynamic> : <String, dynamic>{};
    final amount = (w['amount'] as num?)?.toDouble() ?? 0;
    final status = (w['status'] ?? 'processing').toString();
    final mode = (w['mode'] ?? '').toString();
    final isUpi = mode == 'upi';

    return Container(
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
                colors: [Colors.orange.withValues(alpha: 0.08), Colors.transparent],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(
                  isUpi ? Icons.qr_code_rounded : Icons.account_balance_rounded,
                  size: 16, color: Colors.orange.shade700,
                ),
                const SizedBox(width: 8),
                Text(isUpi ? 'UPI WITHDRAWAL' : 'BANK WITHDRAWAL',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                        letterSpacing: 1)),
                const Spacer(),
                Text(_fmtAmount(amount),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _userRow(context, user)),
                    _statusBadge(status),
                  ],
                ),
                const SizedBox(height: 10),
                if (isUpi)
                  _detailRow(context, 'UPI ID', (w['upiId'] ?? '—').toString())
                else ...[
                  _detailRow(context, 'Account Holder',
                      (w['accountHolderName'] ?? '—').toString()),
                  _detailRow(context, 'Account No.',
                      (w['accountNumber'] ?? '—').toString()),
                  _detailRow(context, 'IFSC', (w['ifsc'] ?? '—').toString()),
                  if ((w['bankName'] ?? '').toString().isNotEmpty)
                    _detailRow(context, 'Bank',
                        (w['bankName'] ?? '').toString()),
                ],
                _detailRow(context, 'Requested', _fmtDate((w['createdAt'] ?? '').toString())),
                if ((w['processedAt'] ?? '').toString().isNotEmpty)
                  _detailRow(context, 'Processed', _fmtDate((w['processedAt'] ?? '').toString()),
                      valueColor: Colors.green),
                if ((w['failureReason'] ?? '').toString().isNotEmpty)
                  _detailRow(context, 'Reason',
                      (w['failureReason'] ?? '').toString(),
                      valueColor: Colors.red),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewAllBtn(BuildContext context, int total) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: TextButton.icon(
          onPressed: () => setState(() => _showAll = !_showAll),
          icon: Icon(_showAll ? Icons.expand_less : Icons.expand_more,
              size: 18, color: AppColors.cyan),
          label: Text(
            _showAll ? 'Show Less' : 'View All ($total)',
            style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// ── Tab 3: Subscriptions ───────────────────────────────────────────────────────

class _SubscriptionsTab extends StatefulWidget {
  const _SubscriptionsTab();

  @override
  State<_SubscriptionsTab> createState() => _SubscriptionsTabState();
}

class _SubscriptionsTabState extends State<_SubscriptionsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<dynamic> _subs = [];
  bool _loading = true;
  String? _error;
  bool _showAll = false;
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final params = '/api/admin/subscriptions${_search.isNotEmpty ? '?search=${Uri.encodeComponent(_search)}' : ''}';
      final res = await ApiClient.get(params);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body);
        final list = raw is List ? raw : (raw['subscriptions'] ?? raw['data'] ?? []);
        setState(() { _subs = list as List; _loading = false; });
      } else {
        setState(() { _error = 'Failed to load subscriptions.'; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = 'Network error.'; _loading = false; });
    }
  }

  List<dynamic> get _filtered {
    final now = DateTime.now();
    return _subs.where((s) {
      if (_statusFilter == 'active') {
        final end = DateTime.tryParse((s['endDate'] ?? '').toString());
        if (end == null || end.isBefore(now)) return false;
      } else if (_statusFilter == 'expired') {
        final end = DateTime.tryParse((s['endDate'] ?? '').toString());
        if (end != null && end.isAfter(now)) return false;
      }
      return true;
    }).toList();
  }

  List<dynamic> get _displayed =>
      _showAll ? _filtered : _filtered.take(3).toList();

  Map<String, dynamic> get _stats {
    final now = DateTime.now();
    int active = 0;
    double totalRev = 0;
    for (final s in _subs) {
      final end = DateTime.tryParse((s['endDate'] ?? '').toString());
      if (end != null && end.isAfter(now)) active++;
      totalRev += ((s['actualPrice'] ?? s['price'] ?? 0) as num).toDouble();
    }
    return {'active': active, 'total': _subs.length, 'revenue': totalRev};
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = _stats;

    return RefreshIndicator(
      onRefresh: _fetch,
      color: AppColors.cyan,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                _summaryRow(context, [
                  _StatChip('Total', s['total'].toString(), AppColors.cyan),
                  _StatChip('Active', s['active'].toString(), Colors.green),
                  _StatChip('Revenue', _fmtAmount(s['revenue']), Colors.purple),
                ]),
                _searchBar(context, _searchCtrl, () {
                  setState(() { _search = _searchCtrl.text; _showAll = false; });
                  Future.delayed(const Duration(milliseconds: 600), _fetch);
                }),
                _statusChips(context),
                const SizedBox(height: 4),
              ],
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: AppColors.cyan)))
          else if (_error != null)
            SliverFillRemaining(
                child: Center(child: Text(_error!, style: const TextStyle(color: Colors.red))))
          else if (_filtered.isEmpty)
            const SliverFillRemaining(child: Center(child: Text('No subscriptions found.')))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    if (i == _displayed.length) {
                      return _viewAllBtn(context, _filtered.length);
                    }
                    return _subCard(ctx, _displayed[i] as Map<String, dynamic>);
                  },
                  childCount: _displayed.length + (_filtered.length > 3 ? 1 : 0),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusChips(BuildContext context) {
    const opts = [
      {'v': 'all', 'l': 'All'},
      {'v': 'active', 'l': 'Active'},
      {'v': 'expired', 'l': 'Expired'},
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: opts.map((o) {
          final sel = _statusFilter == o['v'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() { _statusFilter = o['v']!; _showAll = false; }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: sel ? AppColors.cyan : AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: sel ? AppColors.cyan : AppThemeColors.divider(context)),
                ),
                child: Text(o['l']!,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : AppThemeColors.secondaryText(context))),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _subCard(BuildContext context, Map<String, dynamic> sub) {
    final user = (sub['user'] is Map) ? sub['user'] as Map<String, dynamic> : <String, dynamic>{};
    final plan = (sub['subscriptionPlan'] ?? '—').toString();
    final price = (sub['actualPrice'] ?? sub['price'] ?? 0);
    final endDate = (sub['endDate'] ?? '').toString();
    final payMethod = (sub['paymentMethod'] ?? 'razorpay').toString();
    final payId = (sub['razorpayPaymentId'] ?? '').toString();
    final subDate = (sub['subscribedDate'] ?? sub['createdAt'] ?? '').toString();
    final now = DateTime.now();
    final end = DateTime.tryParse(endDate);
    final isActive = end != null && end.isAfter(now);
    final statusLabel = isActive ? 'active' : 'expired';

    return Container(
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
                colors: [Colors.purple.withValues(alpha: 0.08), Colors.transparent],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.card_membership_rounded, size: 16, color: Colors.purple),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(plan.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                          letterSpacing: 1),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                _statusBadge(statusLabel),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: _userRow(context, user)),
                    Text(_fmtAmount(price),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple)),
                  ],
                ),
                const SizedBox(height: 10),
                _detailRow(context, 'Plan', plan),
                _detailRow(context, 'Payment Method', _prettyMethod(payMethod)),
                if (payId.isNotEmpty)
                  _detailRow(context, 'Payment ID', payId, valueColor: AppColors.cyan),
                _detailRow(context, 'Subscribed On', _fmtDate(subDate)),
                _detailRow(context, 'Expires On',
                    _fmtDate(endDate),
                    valueColor: isActive ? Colors.green : Colors.red),
                if ((sub['duration'] as num?) != null)
                  _detailRow(context, 'Duration', '${sub['duration']} days'),
                if ((sub['free'] as num?)?.toInt() != null &&
                    (sub['free'] as num).toInt() > 0)
                  _detailRow(context, 'Free Days', '${sub['free']} days'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _prettyMethod(String m) {
    switch (m) {
      case 'razorpay_manual': return 'Razorpay (Manual)';
      case 'razorpay': return 'Razorpay';
      case 'wallet': return 'LenDen Wallet';
      default: return m;
    }
  }

  Widget _viewAllBtn(BuildContext context, int total) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: TextButton.icon(
          onPressed: () => setState(() => _showAll = !_showAll),
          icon: Icon(_showAll ? Icons.expand_less : Icons.expand_more,
              size: 18, color: AppColors.cyan),
          label: Text(
            _showAll ? 'Show Less' : 'View All ($total)',
            style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
