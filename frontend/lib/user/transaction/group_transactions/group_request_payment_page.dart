import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../utils/api_client.dart';
import '../../../utils/theme_helper.dart';

final _oidReq = RegExp(r'^[0-9a-f]{24}$');

class GroupRequestPaymentPage extends StatefulWidget {
  final String groupId;
  final String groupTitle;
  final Color groupColor;
  final Map<String, dynamic> initialGroup;
  final String userEmail;

  const GroupRequestPaymentPage({
    super.key,
    required this.groupId,
    required this.groupTitle,
    required this.groupColor,
    required this.initialGroup,
    required this.userEmail,
  });

  @override
  State<GroupRequestPaymentPage> createState() => _GroupRequestPaymentPageState();
}

class _GroupRequestPaymentPageState extends State<GroupRequestPaymentPage> {
  late Map<String, dynamic> _group;
  bool _refreshing = false;
  String _search = '';
  bool _sortDesc = true;
  final Set<String> _requestedEmails = {};
  final Set<String> _loadingEmails = {};
  bool _notifyingAll = false;

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
      final email = _reqResolveEmail(m['user'] ?? m).toLowerCase();
      if (email.contains('@')) net[email] = 0;
    }
    final creator = _group['creator'];
    if (creator != null) {
      final ce = _reqResolveEmail(creator).toLowerCase();
      if (ce.contains('@')) net.putIfAbsent(ce, () => 0);
    }
    for (final exp in expenses) {
      final addedByEmail = _reqResolveEmail(exp['addedBy']).toLowerCase();
      final splits = List<dynamic>.from(exp['split'] ?? []);
      for (final s in splits) {
        final splitEmail = _reqResolveEmail(s['user']).toLowerCase();
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

  // Resolves any user field to an email address, falling back to member-list ObjectId lookup.
  String _reqResolveEmail(dynamic field) {
    if (field == null) return '';
    if (field is String && field.contains('@')) return field;
    if (field is Map) {
      final e = (field['email'] ?? '').toString();
      if (e.contains('@') && !_oidReq.hasMatch(e)) return e;
    }
    final String rawId = field is Map
        ? (field['_id'] ?? field['id'] ?? '').toString()
        : field.toString();
    if (rawId.isNotEmpty && _oidReq.hasMatch(rawId)) {
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
      final e = _reqResolveEmail(m['user'] ?? m).toLowerCase();
      if (e == emailL) {
        final name = ((m['name'] ?? (m['user'] is Map ? m['user']['name'] : '') ?? '') as String).trim();
        return name.isNotEmpty ? name : email;
      }
    }
    final creator = _group['creator'];
    if (creator != null) {
      final ce = _reqResolveEmail(creator).toLowerCase();
      if (ce == emailL) {
        final name = (creator is Map ? (creator['name'] ?? '') : '').toString().trim();
        return name.isNotEmpty ? name : email;
      }
    }
    return email;
  }

  String _initialsFor(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Future<void> _requestFrom(String email, double amount) async {
    if (_loadingEmails.contains(email)) return;
    setState(() => _loadingEmails.add(email));
    try {
      final res = await ApiClient.post(
        '/api/group-transactions/${widget.groupId}/request-payment',
        body: {
          'targets': [{'email': email, 'amount': amount}],
        },
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _requestedEmails.add(email));
        _showSnack('Payment request sent to ${_nameFor(email)}!', success: true);
      } else {
        final err = (jsonDecode(res.body) as Map?)?['error'] ?? 'Failed to send request';
        _showSnack(err.toString(), success: false);
      }
    } catch (_) {
      if (mounted) _showSnack('Connection error. Please try again.', success: false);
    } finally {
      if (mounted) setState(() => _loadingEmails.remove(email));
    }
  }

  Future<void> _requestAll(List<Map<String, dynamic>> pairs) async {
    if (_notifyingAll || pairs.isEmpty) return;
    setState(() => _notifyingAll = true);
    try {
      final targets = pairs.map((p) => {'email': p['from'], 'amount': p['amount']}).toList();
      final res = await ApiClient.post(
        '/api/group-transactions/${widget.groupId}/request-payment',
        body: {'targets': targets},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        for (final p in pairs) _requestedEmails.add(p['from'].toString());
        setState(() {});
        _showSnack('Reminder sent to ${pairs.length} member(s)!', success: true);
      } else {
        final err = (jsonDecode(res.body) as Map?)?['error'] ?? 'Failed to send requests';
        _showSnack(err.toString(), success: false);
      }
    } catch (_) {
      if (mounted) _showSnack('Connection error. Please try again.', success: false);
    } finally {
      if (mounted) setState(() => _notifyingAll = false);
    }
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
    // Pairs where current user is the creditor (others owe them)
    final owedPairs = allPairs.where((p) => p['to'].toString().toLowerCase() == myEmail).toList();

    var filtered = owedPairs.where((p) {
      if (_search.isEmpty) return true;
      final name = _nameFor(p['from'].toString()).toLowerCase();
      return name.contains(_search.toLowerCase()) || p['from'].toString().toLowerCase().contains(_search.toLowerCase());
    }).toList();

    filtered.sort((a, b) {
      final aAmt = (a['amount'] as num).toDouble();
      final bAmt = (b['amount'] as num).toDouble();
      return _sortDesc ? bAmt.compareTo(aAmt) : aAmt.compareTo(bAmt);
    });

    final unrequested = filtered.where((p) => !_requestedEmails.contains(p['from'].toString())).toList();
    final totalOwed = owedPairs.fold<double>(0, (sum, p) => sum + (p['amount'] as num).toDouble());

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
                              child: const Icon(Icons.send_to_mobile_rounded, color: Colors.white, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Request Payment', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                                Text(widget.groupTitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                                if (owedPairs.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('Total owed: ₹${totalOwed.toStringAsFixed(2)}',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ],
                            )),
                            if (unrequested.isNotEmpty)
                              ElevatedButton.icon(
                                onPressed: _notifyingAll ? null : () => _requestAll(unrequested),
                                icon: _notifyingAll
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.notifications_active_rounded, size: 16),
                                label: Text(_notifyingAll ? 'Sending...' : 'Notify All',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: widget.groupColor,
                                  disabledBackgroundColor: Colors.white70,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                              ),
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
                    Icon(Icons.people_outline_rounded, size: 16, color: AppThemeColors.mutedText(context)),
                    const SizedBox(width: 6),
                    Text('${filtered.length} ${filtered.length == 1 ? 'member owes' : 'members owe'} you',
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

            if (owedPairs.isEmpty)
              SliverFillRemaining(
                child: _emptyState(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'Everyone is settled up!',
                  subtitle: 'No one owes you money in this group right now.',
                ),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                child: _emptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No match found',
                  subtitle: 'Try a different name or email.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _memberCard(filtered[i]),
                    childCount: filtered.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
      ),
    );
  }

  Widget _memberCard(Map<String, dynamic> pair) {
    final email = pair['from'].toString();
    final amount = (pair['amount'] as num).toDouble();
    final name = _nameFor(email);
    final initials = _initialsFor(name);
    final isRequested = _requestedEmails.contains(email);
    final isLoading = _loadingEmails.contains(email);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
        border: isRequested
            ? Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.35), width: 1.5)
            : Border.all(color: Colors.transparent),
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
                color: const Color(0xFFE53935).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Owes you ₹${amount.toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFFE53935), fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ])),
          const SizedBox(width: 12),
          // Action
          if (isRequested)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.35)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 16),
                SizedBox(width: 4),
                Text('Sent', style: TextStyle(color: Color(0xFF2E7D32), fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
            )
          else
            ElevatedButton.icon(
              onPressed: isLoading ? null : () => _requestFrom(email, amount),
              icon: isLoading
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.notifications_active_rounded, size: 16),
              label: const Text('Request', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.groupColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: widget.groupColor.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              ),
            ),
        ]),
      ),
    );
  }
}
