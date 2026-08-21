import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String _appVersion = '1.0.0';
  static const String _buildNumber = '100';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: t('about_lenden')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App identity card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.cyan, Color(0xFF0096B4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      size: 44,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'LenDen',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t('app_tagline'),
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onLongPress: () {
                      Clipboard.setData(const ClipboardData(
                          text: 'LenDen v$_appVersion (build $_buildNumber)'));
                      showSnack(context, t('version_copied'));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Version $_appVersion (Build $_buildNumber)',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // What is LenDen
            _buildSection(
              context,
              t('what_is_lenden'),
              Icons.info_outline_rounded,
              AppColors.cyan,
              [
                _buildTextBlock(context, t('what_is_lenden_body')),
              ],
            ),

            const SizedBox(height: 16),

            // Core features
            _buildSection(
              context,
              t('core_features'),
              Icons.star_rounded,
              Colors.orange,
              [
                _buildFeatureRow(context, Icons.swap_horiz_rounded,
                    t('feature_quick_tx_title'), t('feature_quick_tx_desc')),
                _buildFeatureRow(context, Icons.lock_rounded,
                    t('feature_secure_tx_title'), t('feature_secure_tx_desc')),
                _buildFeatureRow(
                    context,
                    Icons.group_rounded,
                    t('feature_group_expenses_title'),
                    t('feature_group_expenses_desc')),
                _buildFeatureRow(
                    context,
                    Icons.account_balance_wallet_rounded,
                    t('feature_wallet_title'),
                    t('feature_wallet_desc')),
                _buildFeatureRow(context, Icons.credit_card_rounded,
                    t('feature_razorpay_title'), t('feature_razorpay_desc')),
                _buildFeatureRow(context, Icons.analytics_rounded,
                    t('feature_analytics_title'), t('feature_analytics_desc')),
                _buildFeatureRow(
                    context,
                    Icons.leaderboard_rounded,
                    t('feature_leaderboard_title'),
                    t('feature_leaderboard_desc')),
                _buildFeatureRow(context, Icons.card_giftcard_rounded,
                    t('feature_gift_cards_title'), t('feature_gift_cards_desc')),
                _buildFeatureRow(context, Icons.pie_chart_rounded,
                    t('feature_budget_title'), t('feature_budget_desc')),
                _buildFeatureRow(context, Icons.cake_rounded,
                    t('feature_birthday_title'), t('feature_birthday_desc')),
                _buildFeatureRow(context, Icons.monetization_on_rounded,
                    t('feature_coins_title'), t('feature_coins_desc')),
                _buildFeatureRow(context, Icons.people_alt_rounded,
                    t('feature_referral_title'), t('feature_referral_desc')),
                _buildFeatureRow(context, Icons.qr_code_scanner_rounded,
                    t('feature_qr_title'), t('feature_qr_desc')),
                _buildFeatureRow(context, Icons.login_rounded,
                    t('feature_google_signin_title'), t('feature_google_signin_desc')),
              ],
            ),

            const SizedBox(height: 16),

            // Security & Privacy
            _buildSection(
              context,
              t('security_and_privacy'),
              Icons.shield_rounded,
              Colors.green,
              [
                _buildTextBlock(context, t('security_privacy_intro')),
                const SizedBox(height: 8),
                _buildBullet(context, t('security_bullet_jwt')),
                _buildBullet(context, t('security_bullet_bcrypt')),
                _buildBullet(context, t('security_bullet_https')),
                _buildBullet(context, t('security_bullet_mongo')),
                _buildBullet(context, t('security_bullet_razorpay')),
                _buildBullet(context, t('security_bullet_otp')),
                _buildBullet(context, t('security_bullet_device')),
                _buildBullet(context, t('security_bullet_helmet')),
                _buildBullet(context, t('security_bullet_nosql')),
                _buildBullet(context, t('security_bullet_ratelimit')),
                _buildBullet(context, t('security_bullet_pin')),
              ],
            ),

            const SizedBox(height: 16),

            // Technology Stack
            _buildSection(
              context,
              t('built_with'),
              Icons.code_rounded,
              Colors.purple,
              [
                _buildTechRow(context, 'Flutter', t('tech_flutter_desc')),
                _buildTechRow(context, 'Node.js + Express', t('tech_node_desc')),
                _buildTechRow(context, 'MongoDB', t('tech_mongo_desc')),
                _buildTechRow(context, 'Razorpay', t('tech_razorpay_desc')),
                _buildTechRow(context, 'Socket.io', t('tech_socketio_desc')),
                _buildTechRow(context, 'JWT', t('tech_jwt_desc')),
                _buildTechRow(context, 'Nodemailer', t('tech_nodemailer_desc')),
                _buildTechRow(context, 'Firebase (FCM)', t('tech_firebase_desc')),
              ],
            ),

            const SizedBox(height: 16),

            // Legal
            _buildSection(
              context,
              t('legal'),
              Icons.gavel_rounded,
              Colors.blueGrey,
              [
                _buildLinkRow(context, t('terms_of_service'),
                    Icons.description_outlined, '/terms'),
                _buildLinkRow(context, t('privacy_policy'),
                    Icons.privacy_tip_outlined, '/privacy'),
              ],
            ),

            const SizedBox(height: 16),

            // Made with love
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Icon(Icons.favorite_rounded,
                      color: Colors.red, size: 28),
                  const SizedBox(height: 10),
                  Text(
                    t('made_with_love_in_india'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '© ${DateTime.now().year} LenDen. ${t('all_rights_reserved')}',
                    style: TextStyle(
                        fontSize: 12, color: AppThemeColors.secondaryText(context)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, IconData icon,
      Color color, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextBlock(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
          fontSize: 14, color: AppThemeColors.primaryText(context), height: 1.5),
    );
  }

  Widget _buildBullet(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ',
              style: TextStyle(
                  color: AppColors.cyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13, color: AppThemeColors.primaryText(context))),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(
      BuildContext context, IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.orange, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppThemeColors.primaryText(context))),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: AppThemeColors.secondaryText(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechRow(BuildContext context, String name, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: Colors.purple, size: 16),
          const SizedBox(width: 10),
          Text(name,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppThemeColors.primaryText(context))),
          const SizedBox(width: 6),
          Expanded(
            child: Text('— $desc',
                style: TextStyle(
                    fontSize: 12, color: AppThemeColors.secondaryText(context))),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkRow(
      BuildContext context, String title, IconData icon, String route) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.blueGrey, size: 20),
      title: Text(title,
          style: TextStyle(
              fontSize: 14,
              color: AppThemeColors.primaryText(context),
              fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: () => Navigator.pushNamed(context, route),
    );
  }
}
