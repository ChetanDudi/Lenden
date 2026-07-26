import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../session.dart';
import '../../../widgets/premium_gate.dart';

class FinancialHealthTab extends StatelessWidget {
  final Map<String, dynamic>? insights;
  final String Function(num?) ca;

  const FinancialHealthTab({super.key, required this.insights, required this.ca});

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('smart_insights')) {
      return const PremiumTabGate(
        featureName: 'Financial Health Score',
        description: 'Get a comprehensive score and breakdown of your financial wellbeing.',
        icon: Icons.favorite_outline_rounded,
        accentColor: Colors.teal,
      );
    }

    final health = insights?['financialHealth'] as Map<String, dynamic>? ?? {};
    final score  = (health['score'] as num?)?.toDouble() ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildScoreCard(context, health, score),
        const SizedBox(height: 16),
        _buildComponentScores(context, health),
        const SizedBox(height: 16),
        _buildImprovementActions(context, health),
        const SizedBox(height: 16),
        _buildScoreFactorsInfo(context),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildScoreCard(BuildContext context, Map<String, dynamic> health, double score) {
    final grade   = health['grade']  as String? ?? 'C';
    final message = health['message'] as String? ?? 'Keep improving your financial habits.';

    Color gradeColor() {
      if (score >= 80) return Colors.teal;
      if (score >= 60) return Colors.orange;
      return Colors.red;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [gradeColor().withValues(alpha: 0.12), gradeColor().withValues(alpha: 0.04)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: gradeColor().withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        SizedBox(
          width: 90, height: 90,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 7,
              backgroundColor: gradeColor().withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(gradeColor()),
            )),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(grade, style: TextStyle(fontSize: context.sp(26), fontWeight: FontWeight.bold, color: gradeColor())),
              Text('${score.toStringAsFixed(0)}/100', style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
            ]),
          ]),
        ),
        const SizedBox(width: 18),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Financial Health Score', style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 6),
          Text(message, style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context), height: 1.4)),
          const SizedBox(height: 8),
          _gradeLegend(context),
        ])),
      ]),
    );
  }

  Widget _gradeLegend(BuildContext context) => Wrap(spacing: 8, children: [
    _gradeChip(context, 'A', Colors.teal, '80+'),
    _gradeChip(context, 'B', Colors.lightGreen, '65+'),
    _gradeChip(context, 'C', Colors.orange, '50+'),
    _gradeChip(context, 'D', Colors.red, '<50'),
  ]);

  Widget _gradeChip(BuildContext context, String g, Color c, String range) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 16, height: 16, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
        child: Center(child: Text(g, style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)))),
    const SizedBox(width: 2),
    Text(range, style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
  ]);

  Widget _buildComponentScores(BuildContext context, Map<String, dynamic> health) {
    final components = (health['components'] as Map?)?.cast<String, dynamic>() ?? {};
    if (components.isEmpty) return const SizedBox.shrink();

    const labels = {
      'budgetAdherence': ('Budget Adherence', Icons.account_balance_wallet_outlined, Colors.deepPurple),
      'savingsRate':     ('Savings Rate',      Icons.savings_outlined,               Colors.teal),
      'spendingControl': ('Spending Control',  Icons.tune_rounded,                   Colors.orange),
      'consistency':     ('Consistency',       Icons.repeat_rounded,                 AppColors.cyan),
      'goalProgress':    ('Goal Progress',     Icons.flag_outlined,                  Colors.pink),
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Score Breakdown', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeColors.border(context)),
        ),
        child: Column(
          children: components.entries.map((e) {
            final meta  = labels[e.key] ?? (e.key, Icons.star_outline, AppColors.cyan);
            final score = (e.value as num?)?.toDouble() ?? 0;
            final color = meta.$3;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Icon(meta.$2, size: 16, color: color),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(meta.$1, style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.w500, color: AppThemeColors.primaryText(context))),
                    const Spacer(),
                    Text('${score.toStringAsFixed(0)}/100', style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.bold, color: color)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: score / 100, minHeight: 5,
                      backgroundColor: AppThemeColors.border(context),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ])),
              ]),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  Widget _buildScoreFactorsInfo(BuildContext context) {
    const factors = [
      (Icons.account_balance_wallet_outlined, Colors.deepPurple, 'Budget Adherence',
        'How well your actual spending matches your set budget limits each month.'),
      (Icons.savings_outlined,               Colors.teal,        'Savings Rate',
        'Percentage of your income that goes to savings goals or surplus balance.'),
      (Icons.tune_rounded,                   Colors.orange,      'Spending Control',
        'Consistency in avoiding impulsive or unusually large one-off expenses.'),
      (Icons.repeat_rounded,                 AppColors.cyan,     'Consistency',
        'How regularly you track spending and stay within category limits over time.'),
      (Icons.flag_outlined,                  Colors.pink,        'Goal Progress',
        'Whether your active savings goals are on track to hit their targets.'),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('What Affects Your Score', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeColors.border(context)),
        ),
        child: Column(
          children: factors.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 32, height: 32,
                decoration: BoxDecoration(color: f.$2.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
                child: Icon(f.$1, size: 15, color: f.$2)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.$3, style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
                const SizedBox(height: 2),
                Text(f.$4, style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context), height: 1.4)),
              ])),
            ]),
          )).toList(),
        ),
      ),
    ]);
  }

  Widget _buildImprovementActions(BuildContext context, Map<String, dynamic> health) {
    final actions = (health['improvementActions'] as List? ?? []).cast<String>();
    if (actions.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Improvement Actions', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeColors.border(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: actions.indexed.map((ia) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 20, height: 20,
                decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Center(child: Text('${ia.$1 + 1}', style: TextStyle(fontSize: context.sp(9), color: AppColors.cyan, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(ia.$2, style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.primaryText(context), height: 1.4))),
            ]),
          )).toList(),
        ),
      ),
    ]);
  }
}
