import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../session.dart';
import '../../../widgets/premium_gate.dart';

class MembersTab extends StatelessWidget {
  final Map<String, dynamic>? report;
  final String Function(num?) ca;

  const MembersTab({super.key, required this.report, required this.ca});

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('reports')) {
      return const PremiumTabGate(
        featureName: 'Member Analytics',
        description: 'See who you transact with most, net balances, and counterparty insights.',
        icon: Icons.people_outline_rounded,
        accentColor: AppColors.cyan,
      );
    }
    if (report == null) {
      return Center(child: Text('No data for this period',
          style: TextStyle(color: AppThemeColors.secondaryText(context))));
    }
    final cps = (report!['topCounterparties'] as List? ?? []).cast<Map<String, dynamic>>();
    if (cps.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.people_outline_rounded, size: 56, color: AppThemeColors.secondaryText(context)),
            const SizedBox(height: 12),
            Text('No counterparty data yet', textAlign: TextAlign.center,
                style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: context.sp(14))),
          ]),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Top Contacts',
                style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          ),
          for (int i = 0; i < cps.length; i++) ...[
            _cpRow(context, cps[i]),
            if (i < cps.length - 1) Divider(color: AppThemeColors.divider(context), height: 20),
          ],
        ]),
      ),
    );
  }

  Widget _cpRow(BuildContext context, Map<String, dynamic> cp) {
    final net      = (cp['netAmount'] as num? ?? 0).toDouble();
    final count    = cp['count'] as int? ?? 0;
    final email    = cp['email']?.toString() ?? '-';
    final initials = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [AppColors.cyan, AppColors.cyan.withValues(alpha: 0.6)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(child: Text(initials,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(email,
            style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context)),
            overflow: TextOverflow.ellipsis),
        Text('$count transactions',
            style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(ca(net.abs()),
            style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold,
                color: net >= 0 ? Colors.teal : Colors.orange)),
        Text(net >= 0 ? 'owes you' : 'you owe',
            style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
      ]),
    ]);
  }
}
