import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';

class OverviewTab extends StatelessWidget {
  final Map<String, dynamic>? report;
  final String Function(num?) ca;

  const OverviewTab({super.key, required this.report, required this.ca});

  @override
  Widget build(BuildContext context) {
    if (report == null) {
      return Center(child: Text('No data for this period',
          style: TextStyle(color: AppThemeColors.secondaryText(context))));
    }
    return RefreshIndicator(
      onRefresh: () async {},
      color: AppColors.cyan,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        child: Column(children: [
          _buildQuickStatsStrip(context),
          const SizedBox(height: 14),
          _buildOverviewCards(context),
          const SizedBox(height: 14),
          _buildAdvancedStats(context),
          const SizedBox(height: 14),
          _buildSpendingPersonality(context),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _buildQuickStatsStrip(BuildContext context) {
    final ov = report!['overview'] as Map<String, dynamic>? ?? {};
    final total = (ov['totalTransactions'] as num? ?? 0).toInt();
    final cleared = (ov['clearedTransactions'] as num? ?? 0).toInt();
    final lent = (ov['totalAmountLent'] as num? ?? 0).toDouble();
    final borrowed = (ov['totalAmountBorrowed'] as num? ?? 0).toDouble();
    final allAmt = lent + borrowed;
    final avg = total > 0 ? allAmt / total : 0.0;
    final settlePct = total > 0 ? (cleared / total * 100).toInt() : 0;
    final trend = (report!['monthlyTrend'] as List? ?? []).cast<Map<String, dynamic>>();
    String peakMonth = '-';
    if (trend.isNotEmpty) {
      final peak = trend.reduce((a, b) {
        final aV = (a['lent'] as num? ?? 0) + (a['borrowed'] as num? ?? 0);
        final bV = (b['lent'] as num? ?? 0) + (b['borrowed'] as num? ?? 0);
        return aV >= bV ? a : b;
      });
      peakMonth = peak['label'] as String? ?? '-';
    }

    return Row(children: [
      Expanded(child: _quickStatPill(context, Icons.check_circle_outline, '$settlePct%', 'Settled', Colors.teal)),
      const SizedBox(width: 8),
      Expanded(child: _quickStatPill(context, Icons.calculate_outlined, ca(avg), 'Avg Txn', AppColors.cyan)),
      const SizedBox(width: 8),
      Expanded(child: _quickStatPill(context, Icons.calendar_month_outlined, peakMonth, 'Peak Month', Colors.deepPurple)),
    ]);
  }

  Widget _quickStatPill(BuildContext context, IconData icon, String value, String label, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis, maxLines: 1),
          Text(label, style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
        ]),
      );

  Widget _buildOverviewCards(BuildContext context) {
    final ov = report!['overview'] as Map<String, dynamic>? ?? {};
    final net = (ov['netBalance'] as num? ?? 0).toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle(context, 'Overview'),
      Row(children: [
        Expanded(child: _statCard(context, 'Transactions', '${ov['totalTransactions'] ?? 0}', AppColors.cyan, Icons.receipt_long_outlined)),
        const SizedBox(width: 10),
        Expanded(child: _statCard(context, 'Net Balance', ca(net.abs()), net >= 0 ? Colors.green : Colors.red, net >= 0 ? Icons.trending_up : Icons.trending_down)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _statCard(context, 'Total Lent', ca(ov['totalAmountLent']), Colors.teal, Icons.arrow_upward_rounded)),
        const SizedBox(width: 10),
        Expanded(child: _statCard(context, 'Total Borrowed', ca(ov['totalAmountBorrowed']), Colors.orange, Icons.arrow_downward_rounded)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _statCard(context, 'Group Expenses', ca(ov['groupExpenseTotal']), Colors.purple, Icons.group_outlined)),
        const SizedBox(width: 10),
        Expanded(child: _statCard(context, 'Your Group Share', ca(ov['groupUserShare']), Colors.deepPurple, Icons.person_outlined)),
      ]),
    ]);
  }

  Widget _statCard(BuildContext context, String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 32, height: 32,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 18)),
          const Spacer(),
        ]),
        const SizedBox(height: 10),
        Text(value, style: TextStyle(fontSize: context.sp(17), fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
      ]),
    );
  }

  Widget _buildAdvancedStats(BuildContext context) {
    final adv = report!['advanced'] as Map<String, dynamic>? ?? {};
    final ov = report!['overview'] as Map<String, dynamic>? ?? {};
    if ((adv['highestTxn'] as num? ?? 0) == 0) return const SizedBox.shrink();

    final items = [
      (ca(adv['highestTxn']), 'Highest Txn', Icons.arrow_circle_up_outlined, Colors.red.shade400),
      (ca(adv['lowestTxn']), 'Lowest Txn', Icons.arrow_circle_down_outlined, Colors.teal),
      (ca(adv['avgTxn']), 'Avg Transaction', Icons.calculate_outlined, AppColors.cyan),
      (ca(adv['avgDailySpend']), 'Avg Daily Vol', Icons.today_rounded, Colors.indigo),
      (ca(ov['pendingAmount']), 'Pending Dues', Icons.pending_actions_rounded, Colors.orange),
      ('${adv['daysInPeriod']} days', 'Period Length', Icons.date_range_rounded, Colors.purple),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle(context, 'Advanced Stats'),
        GridView.count(
          crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.35,
          children: items.map((item) => Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: item.$4.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: item.$4.withValues(alpha: 0.2)),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(item.$3, color: item.$4, size: 18),
              const SizedBox(height: 4),
              Text(item.$1, style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.bold, color: item.$4), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
              Text(item.$2, style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context)), textAlign: TextAlign.center),
            ]),
          )).toList(),
        ),
      ]),
    );
  }

  Widget _buildSpendingPersonality(BuildContext context) {
    final ov = report!['overview'] as Map<String, dynamic>? ?? {};
    final lent = (ov['totalAmountLent'] as num? ?? 0).toDouble();
    final borrowed = (ov['totalAmountBorrowed'] as num? ?? 0).toDouble();
    final groupShare = (ov['groupUserShare'] as num? ?? 0).toDouble();
    final net = lent - borrowed;

    String label, desc;
    IconData icon;
    Color color;

    if (groupShare > lent + borrowed) {
      label = 'Group Spender'; icon = Icons.group_outlined; color = Colors.deepPurple;
      desc = 'Most of your activity is in group expenses. You\'re a social spender who splits costs often.';
    } else if (lent > borrowed * 1.5 || (borrowed == 0 && lent > 0)) {
      label = 'Active Lender'; icon = Icons.trending_up_rounded; color = Colors.teal;
      desc = 'You lend more than you borrow — people rely on you when they need funds.';
    } else if (borrowed > lent * 1.5 || (lent == 0 && borrowed > 0)) {
      label = 'Frequent Borrower'; icon = Icons.trending_down_rounded; color = Colors.orange;
      desc = 'You borrow more than you lend. Consider settling your dues to maintain trust.';
    } else if (net.abs() < (lent + borrowed) * 0.1) {
      label = 'Balanced Transactor'; icon = Icons.balance_rounded; color = AppColors.cyan;
      desc = 'You have a healthy mix of lending and borrowing — nearly perfectly balanced.';
    } else {
      label = 'Regular User'; icon = Icons.person_outline_rounded; color = Colors.indigo;
      desc = 'You use LenDen regularly. Keep tracking to get better insights over time.';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0.04)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your Money Persona', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: context.sp(16), fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(desc, style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context), height: 1.4)),
        ])),
      ]),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
  );
}

