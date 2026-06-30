import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/wave_widget.dart'
    show MediumTopWaveClipper, AltBottomWaveClipper;
import 'subscription_plans_tab.dart';
import 'premium_benefits_tab.dart';
import 'faqs_tab.dart';
import 'manage_subscriptions_tab.dart';

class AdminFeaturesPage extends StatefulWidget {
  @override
  _AdminFeaturesPageState createState() => _AdminFeaturesPageState();
}

class _AdminFeaturesPageState extends State<AdminFeaturesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(t('manage_subscription_title'),
            style: TextStyle(
                color: AppThemeColors.primaryText(context),
                fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppThemeColors.primaryText(context),
          unselectedLabelColor:
              AppThemeColors.primaryText(context).withValues(alpha: 0.7),
          indicatorColor: AppColors.cyan,
          indicatorWeight: 3,
          tabs: [
            Tab(text: t('plans_tab'), icon: Icon(Icons.card_membership)),
            Tab(text: t('benefits_tab'), icon: Icon(Icons.star)),
            Tab(text: t('faqs_tab'), icon: Icon(Icons.help_outline)),
            Tab(text: t('subscriptions_tab'), icon: Icon(Icons.subscriptions)),
          ],
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: const MediumTopWaveClipper(),
              child: Container(
                height: context.sh(156),
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipPath(
              clipper: const AltBottomWaveClipper(),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.13,
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          SafeArea(
            child: TabBarView(
              controller: _tabController,
              children: [
                SubscriptionPlansTab(),
                PremiumBenefitsTab(),
                FaqsTab(),
                ManageSubscriptionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
