import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import '../widgets/app_colors.dart';
import '../utils/theme_helper.dart';
import '../utils/responsive.dart';
import '../user/digitise/subscriptions_page.dart';

/// Full-area premium gate shown in place of gated page content.
/// Drop it inside an [Expanded] or sized container.
class PremiumGate extends StatelessWidget {
  final String pageTitle;
  final String badgeLabel;
  final String headline;
  final String subtext;
  final List<_PremiumFeature> features;
  final Color accentColor;

  const PremiumGate({
    super.key,
    required this.pageTitle,
    required this.badgeLabel,
    required this.headline,
    required this.subtext,
    required this.features,
    this.accentColor = AppColors.cyan,
  });

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final plan = session.subscriptionPlan;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Crown card
          Container(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1A1200), const Color(0xFF0D1A2E)]
                    : [const Color(0xFFFFFDE7), const Color(0xFFE3F2FD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.5), width: 1.5),
              boxShadow: [
                BoxShadow(color: const Color(0xFFFFB300).withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6)),
              ],
            ),
            child: Column(children: [
              // Crown icon
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFB300), Color(0xFFFFC107)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [BoxShadow(color: const Color(0xFFFFB300).withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 4))],
                ),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              // Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFFB300), Color(0xFFFF8F00)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(badgeLabel, style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.8)),
              ),
              const SizedBox(height: 14),
              Text(headline,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: context.sp(20), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context), height: 1.2)),
              const SizedBox(height: 8),
              Text(subtext,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: context.sp(13), color: AppThemeColors.secondaryText(context), height: 1.4)),
            ]),
          ),
          const SizedBox(height: 20),
          // Features card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accentColor.withValues(alpha: 0.2)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.diamond_outlined, size: 16, color: accentColor),
                const SizedBox(width: 6),
                Text("What's included", style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
              ]),
              const SizedBox(height: 16),
              ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: f.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(f.icon, size: 15, color: f.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(f.title, style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context))),
                    if (f.subtitle != null)
                      Text(f.subtitle!, style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context), height: 1.3)),
                  ])),
                  const Icon(Icons.check_circle_rounded, size: 16, color: Colors.teal),
                ]),
              )),
            ]),
          ),
          const SizedBox(height: 20),
          // CTA button
          ElevatedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB300),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 3,
              shadowColor: const Color(0xFFFFB300).withValues(alpha: 0.4),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.workspace_premium_rounded, size: 20),
              const SizedBox(width: 8),
              Text('Unlock $pageTitle', style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, letterSpacing: 0.3)),
            ]),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
            child: Text('View all plans →', style: TextStyle(fontSize: context.sp(13), color: accentColor, fontWeight: FontWeight.w600)),
          ),
          // Current plan info (if any)
          if (plan != null && plan.isNotEmpty) ...[
            const SizedBox(height: 8),
            Center(child: Text('Current plan: $plan', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context)))),
          ],
        ],
      ),
    );
  }
}

/// Compact gate for use inside a tab body — smaller than full-page [PremiumGate].
class PremiumTabGate extends StatelessWidget {
  final String featureName;
  final String description;
  final IconData icon;
  final Color accentColor;

  const PremiumTabGate({
    super.key,
    required this.featureName,
    this.description = 'Upgrade to access this feature',
    this.icon = Icons.workspace_premium_rounded,
    this.accentColor = AppColors.cyan,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFFFFB300), Color(0xFFFFC107)]),
                boxShadow: [BoxShadow(color: const Color(0xFFFFB300).withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 34),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFFB300), Color(0xFFFF8F00)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('PREMIUM FEATURE', style: TextStyle(fontSize: context.sp(10), fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.8)),
            ),
            const SizedBox(height: 14),
            Text(featureName,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: context.sp(18), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 8),
            Text(description,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context), height: 1.5)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
                icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                label: Text('Upgrade to Premium', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB300),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
              child: Text('View all plans →', style: TextStyle(fontSize: context.sp(12), color: accentColor)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumFeature {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  const _PremiumFeature(this.icon, this.color, this.title, [this.subtitle]);
}

// ── Pre-built gates for each page ─────────────────────────────────────────────

class ReportsPremiumGate extends StatelessWidget {
  const ReportsPremiumGate({super.key});

  @override
  Widget build(BuildContext context) => PremiumGate(
    pageTitle: 'Reports',
    badgeLabel: '📊 REPORTS PREMIUM',
    headline: 'Unlock Deep Financial Analytics',
    subtext: 'Get complete visibility into your spending, trends, and financial patterns.',
    accentColor: AppColors.cyan,
    features: const [
      _PremiumFeature(Icons.history_rounded, Colors.deepPurple, 'Unlimited Report History', 'Access reports for any period, no limits'),
      _PremiumFeature(Icons.filter_alt_outlined, AppColors.cyan, 'Advanced Filters', 'Filter by category, date, counterparty, amount'),
      _PremiumFeature(Icons.picture_as_pdf_outlined, Colors.red, 'PDF & CSV Export', 'Download reports for any period as PDF or CSV'),
      _PremiumFeature(Icons.dashboard_customize_outlined, Colors.orange, 'Custom Dashboards', 'Pin the metrics that matter most to you'),
      _PremiumFeature(Icons.bar_chart_rounded, Colors.teal, 'Business-Style Analytics', 'Heat maps, weekly comparisons, group analytics'),
    ],
  );
}

class BudgetPremiumGate extends StatelessWidget {
  const BudgetPremiumGate({super.key});

  @override
  Widget build(BuildContext context) => PremiumGate(
    pageTitle: 'Budget Planning',
    badgeLabel: '💰 BUDGET PREMIUM',
    headline: 'Take Full Control of Your Money',
    subtext: 'Set unlimited budgets, track every category, and build towards your savings goals.',
    accentColor: Colors.teal,
    features: const [
      _PremiumFeature(Icons.all_inclusive_rounded, Colors.teal, 'Unlimited Budgets', 'Create budgets for every month without restriction'),
      _PremiumFeature(Icons.category_outlined, Colors.orange, 'Category Budgets', 'Individual limits for Food, Shopping, Travel & more'),
      _PremiumFeature(Icons.group_outlined, Colors.deepPurple, 'Shared Family/Group Budgets', 'Collaborate on budgets with family members'),
      _PremiumFeature(Icons.savings_outlined, AppColors.cyan, 'Advanced Savings Goals', 'Multiple goals with deadlines, tracking, and forecasts'),
      _PremiumFeature(Icons.auto_fix_high_rounded, Colors.indigo, 'Automatic Budget Recommendations', 'AI suggests limits based on your past 3 months'),
    ],
  );
}

class InsightsPremiumGate extends StatelessWidget {
  const InsightsPremiumGate({super.key});

  @override
  Widget build(BuildContext context) => PremiumGate(
    pageTitle: 'Smart Insights',
    badgeLabel: '🧠 SMART INSIGHTS PREMIUM',
    headline: 'Your Personal AI Finance Advisor',
    subtext: 'Get AI-powered advice, spending predictions, and personalized plans tailored to your habits.',
    accentColor: Colors.deepPurple,
    features: const [
      _PremiumFeature(Icons.auto_awesome_rounded, Colors.deepPurple, 'AI-Powered Financial Advice', 'Personalized recommendations based on your data'),
      _PremiumFeature(Icons.auto_graph_rounded, AppColors.cyan, 'Expense Forecasting', 'Predict your month-end spending before it happens'),
      _PremiumFeature(Icons.lightbulb_outline_rounded, Colors.orange, 'Personalized Saving Plans', 'Actionable steps to cut costs and grow savings'),
      _PremiumFeature(Icons.shield_outlined, Colors.teal, 'Financial Health Score', '5-factor score with detailed factor breakdown'),
      _PremiumFeature(Icons.calendar_view_week_rounded, Colors.indigo, 'Weekly & Monthly AI Summaries', 'Intelligent summaries delivered every week'),
    ],
  );
}

class DiscoverPremiumGate extends StatelessWidget {
  const DiscoverPremiumGate({super.key});

  @override
  Widget build(BuildContext context) => PremiumGate(
    pageTitle: 'Discover',
    badgeLabel: '🔍 DISCOVER PREMIUM',
    headline: 'Find & Connect with People',
    subtext: 'Expand your network with AI-powered friend suggestions based on mutual connections and transactions.',
    accentColor: AppColors.cyan,
    features: const [
      _PremiumFeature(Icons.person_search_rounded, AppColors.cyan, 'People You May Know', 'Smart suggestions based on your mutual contacts'),
      _PremiumFeature(Icons.hub_outlined, Colors.deepPurple, 'Network Expansion', 'Discover friends-of-friends and common connections'),
      _PremiumFeature(Icons.star_rounded, Colors.amber, 'Trust Ratings', 'See community ratings before you connect'),
      _PremiumFeature(Icons.verified_rounded, Colors.teal, 'Verified Profiles', 'Connect with verified LenDen members'),
    ],
  );
}
