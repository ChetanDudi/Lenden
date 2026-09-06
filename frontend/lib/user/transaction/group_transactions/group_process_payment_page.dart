import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../utils/api_client.dart';
import '../../../utils/theme_helper.dart';
import '../../wallet/widgets/payment_sheet.dart';

final _oidProc = RegExp(r'^[0-9a-f]{24}$');

String _fmtProcDate(dynamic dt) {
  if (dt == null) return '';
  try {
    final d = dt is String ? DateTime.parse(dt).toLocal() : dt as DateTime;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}  $h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
  } catch (_) {
    return '';
  }
}

class GroupProcessPaymentPage extends StatefulWidget {
  final String groupId;
  final String groupTitle;
  final Color groupColor;
  final Map<String, dynamic> initialGroup;
  final String userEmail;

  const GroupProcessPaymentPage({
    super.key,
    required this.groupId,
    required this.groupTitle,
    required this.groupColor,
    required this.initialGroup,
    required this.userEmail,
  });

  @override
  State<GroupProcessPaymentPage> createState() => _GroupProcessPaymentPageState();
}

class _GroupProcessPaymentPageState extends State<GroupProcessPaymentPage> {
  late Map<String, dynamic> _group;
  bool _refreshing = false;
  String _search = '';
  bool _sortDesc = true;

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup;
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final res = await ApiClient.get('/api/group-transactions/user-groups');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final groups = List<dynamic>.from(data['groups'] ?? data ?? []);
        final found = groups.firstWhere(
          (g) => (g['_id'] ?? '').toString() == widget.groupId,
          orElse: () => null,
        );
        if (found != null) setState(() => _group = Map<String, dynamic>.from(found));
      }
    } catch (_) {}
    if (mounted) setState(() => _refreshing = false);
  }

  Map<String, double> _computeBalances() {
    final expenses = List<dynamic>.from(_group['expenses'] ?? []);
    final members = List<dynamic>.from(_group['members'] ?? []);
    if (expenses.isEmpty) return {};
    final Map<String, double> net = {};
    for (final m in members) {
      final email = _procResolveEmail(m['user'] ?? m).toLowerCase();
      if (email.contains('@')) net[email] = 0;
    }
    final creator = _group['creator'];
    if (creator != null) {
      final ce = _procResolveEmail(creator).toLowerCase();
      if (ce.contains('@')) net.putIfAbsent(ce, () => 0);
    }
    for (final exp in expenses) {
      final addedByEmail = _procResolveEmail(exp['addedBy']).toLowerCase();
      final splits = List<dynamic>.from(exp['split'] ?? []);
      for (final s in splits) {
        final splitEmail = _procResolveEmail(s['user']).toLowerCase();
        final amount = ((s['amount'] ?? 0) as num).toDouble();
        if (s['settled'] == true) continue;
        if (splitEmail.isEmpty || splitEmail == addedByEmail) continue;
        net[splitEmail] = (net[splitEmail] ?? 0) + amount;
        net[addedByEmail] = (net[addedByEmail] ?? 0) - amount;
      }
    }
    for (final p in List<dynamic>.from(_group['memberPayments'] ?? [])) {
      final from = (p['from'] as String? ?? '').toLowerCase();
      final to = (p['to'] as String? ?? '').toLowerCase();
      final amt = ((p['amount'] ?? 0) as num).toDouble();
      net[from] = (net[from] ?? 0) - amt;
      net[to] = (net[to] ?? 0) + amt;
    }
    net.removeWhere((_, v) => v.abs() < 0.01);
    return net;
  }

  List<Map<String, dynamic>> _computePairwiseDebts(Map<String, double> balances) {
    final debtors = <String, double>{};
    final creditors = <String, double>{};
    for (final e in balances.entries) {
      if (e.value > 0.01) debtors[e.key] = e.value;
      if (e.value < -0.01) creditors[e.key] = -e.value;
    }
    final dKeys = debtors.keys.toList();
    final cKeys = creditors.keys.toList();
    final dAmts = dKeys.map((k) => debtors[k]!).toList();
    final cAmts = cKeys.map((k) => creditors[k]!).toList();
    final result = <Map<String, dynamic>>[];
    int di = 0, ci = 0;
    while (di < dKeys.length && ci < cKeys.length) {
      final pay = dAmts[di] < cAmts[ci] ? dAmts[di] : cAmts[ci];
      result.add({'from': dKeys[di], 'to': cKeys[ci], 'amount': pay});
      dAmts[di] -= pay;
      cAmts[ci] -= pay;
      if (dAmts[di] < 0.01) di++;
      if (cAmts[ci] < 0.01) ci++;
    }
    return result;
  }

  // Resolves any user field (ObjectId string, populated Map, or plain email) to an email address.
  // Falls back to searching _group['members'] by ObjectId so un-populated references still resolve.
  String _procResolveEmail(dynamic field) {
    if (field == null) return '';
    if (field is String && field.contains('@')) return field;
    if (field is Map) {
      final e = (field['email'] ?? '').toString();
      if (e.contains('@') && !_oidProc.hasMatch(e)) return e;
    }
    final String rawId = field is Map
        ? (field['_id'] ?? field['id'] ?? '').toString()
        : field.toString();
    if (rawId.isNotEmpty && _oidProc.hasMatch(rawId)) {
      for (final m in List<dynamic>.from(_group['members'] ?? [])) {
        final memberId = (m['_id'] ?? '').toString();
        if (memberId == rawId) {
          final e = (m['email'] ?? '').toString();
          if (e.contains('@')) return e;
        }
        final mUser = m['user'];
        final mId = mUser is Map
            ? (mUser['_id'] ?? mUser['id'] ?? '').toString()
            : (mUser ?? '').toString();
        if (mId.isNotEmpty && mId == rawId) {
          final e = (m['email'] ?? (mUser is Map ? (mUser['email'] ?? '') : '')).toString();
          if (e.contains('@')) return e;
        }
      }
    }
    return '';
  }

  String _nameFor(String email) {
    final emailL = email.toLowerCase();
    for (final m in List<dynamic>.from(_group['members'] ?? [])) {
      final e = _procResolveEmail(m['user'] ?? m).toLowerCase();
      if (e == emailL) {
        final name = ((m['name'] ?? (m['user'] is Map ? m['user']['name'] : '') ?? '') as String).trim();
        return name.isNotEmpty ? name : email;
      }
    }
    final creator = _group['creator'];
    if (creator != null) {
      final ce = _procResolveEmail(creator).toLowerCase();
      if (ce == emailL) {
        final name = (creator is Map ? (creator['name'] ?? '') : '').toString().trim();
        return name.isNotEmpty ? name : email;
      }
    }
    return email;
  }

  String _initialsFor(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2 && parts[1].isNotEmpty) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  void _showSnack(String msg, {required bool success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(success ? Icons.check_circle_rounded : Icons.error_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: success ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(14),
      elevation: 6,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final balances = _computeBalances();
    final allPairs = _computePairwiseDebts(balances);
    final myEmail = widget.userEmail.toLowerCase();
    // Pairs where current user is the debtor (they owe someone)
    final owingPairs = allPairs.where((p) => p['from'].toString().toLowerCase() == myEmail).toList();

    var filtered = owingPairs.where((p) {
      if (_search.isEmpty) return true;
      final name = _nameFor(p['to'].toString()).toLowerCase();
      return name.contains(_search.toLowerCase()) || p['to'].toString().toLowerCase().contains(_search.toLowerCase());
    }).toList();

    filtered.sort((a, b) {
      final aAmt = (a['amount'] as num).toDouble();
      final bAmt = (b['amount'] as num).toDouble();
      return _sortDesc ? bAmt.compareTo(aAmt) : aAmt.compareTo(bAmt);
    });

    final totalOwing = owingPairs.fold<double>(0, (sum, p) => sum + (p['amount'] as num).toDouble());

    // Recent payment history involving current user
    final allPayments = List<dynamic>.from(_group['memberPayments'] ?? []);
    final myPayments = allPayments.where((p) =>
      (p['from'] as String? ?? '').toLowerCase() == myEmail ||
      (p['to'] as String? ?? '').toLowerCase() == myEmail
    ).toList().reversed.take(10).toList();

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: widget.groupColor,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 180,
              pinned: true,
              backgroundColor: widget.groupColor,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                if (_refreshing)
                  const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                else
                  IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: _refresh),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [widget.groupColor, widget.groupColor.withValues(alpha: 0.7)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.payment_rounded, color: Colors.white, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Process Payment', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                                Text(widget.groupTitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                                if (owingPairs.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('You owe: ₹${totalOwing.toStringAsFixed(2)}',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ],
                            )),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Search + Filter bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v),
                      style: TextStyle(color: AppThemeColors.primaryText(context), fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Search members...',
                        hintStyle: TextStyle(color: AppThemeColors.mutedText(context)),
                        prefixIcon: Icon(Icons.search_rounded, color: AppThemeColors.mutedText(context)),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(icon: Icon(Icons.clear_rounded, color: AppThemeColors.mutedText(context)), onPressed: () => setState(() => _search = ''))
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Icon(Icons.account_balance_wallet_outlined, size: 16, color: AppThemeColors.mutedText(context)),
                    const SizedBox(width: 6),
                    Text('You owe ${filtered.length} ${filtered.length == 1 ? 'member' : 'members'}',
                      style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _sortDesc = !_sortDesc),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: widget.groupColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: widget.groupColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_sortDesc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 14, color: widget.groupColor),
                          const SizedBox(width: 4),
                          Text(_sortDesc ? 'Highest First' : 'Lowest First',
                            style: TextStyle(color: widget.groupColor, fontSize: 12, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),

            // Owing list
            if (owingPairs.isEmpty)
              SliverToBoxAdapter(
                child: _emptyState(
                  icon: Icons.check_circle_outline_rounded,
                  title: "You're all settled up!",
                  subtitle: 'You don\'t owe anyone in this group right now.',
                ),
              )
            else if (filtered.isEmpty)
              SliverToBoxAdapter(
                child: _emptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No match found',
                  subtitle: 'Try a different name or email.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _owingCard(filtered[i]),
                    childCount: filtered.length,
                  ),
                ),
              ),

            // Payment history section
            if (myPayments.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(children: [
                    Container(
                      width: 4, height: 20,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [widget.groupColor, widget.groupColor.withValues(alpha: 0.5)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('Payment History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
                    const SizedBox(width: 6),
                    Text('(your transactions)', style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context))),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _paymentHistoryTile(myPayments[i]),
                    childCount: myPayments.length,
                  ),
                ),
              ),
            ] else
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _emptyState({required IconData icon, required String title, required String subtitle}) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(color: widget.groupColor.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 64, color: widget.groupColor),
        ),
        const SizedBox(height: 24),
        Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)), textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text(subtitle, style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 15), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _owingCard(Map<String, dynamic> pair) {
    final email = pair['to'].toString();
    final amount = (pair['amount'] as num).toDouble();
    final name = _nameFor(email);
    final initials = _initialsFor(name);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          // Avatar
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [widget.groupColor, widget.groupColor.withValues(alpha: 0.65)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 2),
            Text(email, style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 12), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE65100).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('You owe ₹${amount.toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFFE65100), fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ])),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () async {
              await LendenPaymentHelper.showPaymentSheet(
                context,
                counterpartyEmail: email,
                amount: amount,
                description: 'Group expense settlement — ${widget.groupTitle}',
                payEndpoint: '/api/group-transactions/${widget.groupId}/record-payment',
                payBody: {'toEmail': email, 'amount': amount},
                onSuccess: () {
                  _refresh();
                  _showSnack('Payment of ₹${amount.toStringAsFixed(2)} sent to $name!', success: true);
                },
              );
            },
            icon: const Icon(Icons.payment_rounded, size: 16),
            label: const Text('Pay Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.groupColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _paymentHistoryTile(dynamic payment) {
    final from = (payment['from'] as String? ?? '').toLowerCase();
    final to = (payment['to'] as String? ?? '').toLowerCase();
    final amt = ((payment['amount'] ?? 0) as num).toDouble();
    final date = _fmtProcDate(payment['paidAt']);
    final isSent = from == widget.userEmail.toLowerCase();
    final counterEmail = isSent ? to : from;
    final counterName = _nameFor(counterEmail);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: (isSent ? const Color(0xFF2E7D32) : const Color(0xFF1565C0)).withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: (isSent ? const Color(0xFF2E7D32) : const Color(0xFF1565C0)).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isSent ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            color: isSent ? const Color(0xFF2E7D32) : const Color(0xFF1565C0),
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isSent ? 'Paid $counterName' : 'Received from $counterName',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppThemeColors.primaryText(context))),
          if (date.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(date, style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
          ],
        ])),
        Text(
          '${isSent ? '-' : '+'}₹${amt.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.bold, fontSize: 14,
            color: isSent ? const Color(0xFF2E7D32) : const Color(0xFF1565C0),
          ),
        ),
      ]),
    );
  }
}
