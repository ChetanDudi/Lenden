import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const String _lastUpdated = 'August 2025';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: t('privacy_policy')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2D6A4F), Color(0xFF40916C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(Icons.privacy_tip_rounded,
                      color: Colors.white, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    t('privacy_policy'),
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${t('pp_last_updated_prefix')} $_lastUpdated',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t('pp_header_intro'),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _buildSection(context, t('pp_s1_title'), Icons.storage_rounded,
                Colors.blue, [
              _buildParagraph(context, t('pp_s1_p1')),
              _buildBullet(context, t('pp_s1_b1')),
              _buildBullet(context, t('pp_s1_b2')),
              _buildBullet(context, t('pp_s1_b3')),
              _buildBullet(context, t('pp_s1_b4')),
              _buildBullet(context, t('pp_s1_b5')),
              const SizedBox(height: 10),
              _buildParagraph(context, t('pp_s1_p2')),
              _buildBullet(context, t('pp_s1_b6')),
              _buildBullet(context, t('pp_s1_b7')),
              _buildBullet(context, t('pp_s1_b8')),
              _buildBullet(context, t('pp_s1_b9')),
            ]),

            _buildSection(
                context, t('pp_s2_title'), Icons.psychology_rounded,
                Colors.purple, [
              _buildParagraph(context, t('pp_s2_p1')),
              _buildBullet(context, t('pp_s2_b1')),
              _buildBullet(context, t('pp_s2_b2')),
              _buildBullet(context, t('pp_s2_b3')),
              _buildBullet(context, t('pp_s2_b4')),
              _buildBullet(context, t('pp_s2_b5')),
              _buildBullet(context, t('pp_s2_b6')),
              _buildBullet(context, t('pp_s2_b7')),
              _buildBullet(context, t('pp_s2_b8')),
            ]),

            _buildSection(
                context, t('pp_s3_title'), Icons.share_rounded, Colors.orange, [
              _buildParagraph(context, t('pp_s3_p1')),
              _buildBullet(context, t('pp_s3_b1')),
              _buildBullet(context, t('pp_s3_b2')),
              _buildBullet(context, t('pp_s3_b3')),
              _buildBullet(context, t('pp_s3_b4')),
              const SizedBox(height: 8),
              _buildParagraph(context, t('pp_s3_p2')),
            ]),

            _buildSection(
                context, t('pp_s4_title'), Icons.shield_rounded, Colors.green, [
              _buildParagraph(context, t('pp_s4_p1')),
              _buildBullet(context, t('pp_s4_b1')),
              _buildBullet(context, t('pp_s4_b2')),
              _buildBullet(context, t('pp_s4_b3')),
              _buildBullet(context, t('pp_s4_b4')),
              _buildBullet(context, t('pp_s4_b5')),
              const SizedBox(height: 8),
              _buildParagraph(context, t('pp_s4_p2')),
            ]),

            _buildSection(context, t('pp_s5_title'), Icons.person_rounded,
                AppColors.cyan, [
              _buildParagraph(context, t('pp_s5_p1')),
              _buildBullet(context, t('pp_s5_b1')),
              _buildBullet(context, t('pp_s5_b2')),
              _buildBullet(context, t('pp_s5_b3')),
              _buildBullet(context, t('pp_s5_b4')),
              _buildBullet(context, t('pp_s5_b5')),
              _buildBullet(context, t('pp_s5_b6')),
            ]),

            _buildSection(
                context, t('pp_s6_title'), Icons.history_rounded, Colors.brown, [
              _buildParagraph(context, t('pp_s6_p1')),
              _buildParagraph(context, t('pp_s6_p2')),
              _buildParagraph(context, t('pp_s6_p3')),
            ]),

            _buildSection(context, t('pp_s7_title'), Icons.cookie_rounded,
                Colors.teal, [
              _buildParagraph(context, t('pp_s7_p1')),
              _buildBullet(context, t('pp_s7_b1')),
              _buildBullet(context, t('pp_s7_b2')),
              _buildBullet(context, t('pp_s7_b3')),
            ]),

            _buildSection(context, t('pp_s8_title'), Icons.child_care_rounded,
                Colors.pink, [
              _buildParagraph(context, t('pp_s8_p1')),
              _buildParagraph(context, t('pp_s8_p2')),
            ]),

            _buildSection(
                context, t('pp_s9_title'), Icons.link_rounded, Colors.indigo, [
              _buildParagraph(context, t('pp_s9_p1')),
              _buildBullet(context, t('pp_s9_b1')),
              _buildBullet(context, t('pp_s9_b2')),
              _buildBullet(context, t('pp_s9_b3')),
              _buildParagraph(context, t('pp_s9_p2')),
            ]),

            _buildSection(
                context, t('pp_s10_title'), Icons.update_rounded, Colors.red,
                [
                  _buildParagraph(context, t('pp_s10_p1')),
                  _buildParagraph(context, t('pp_s10_p2')),
                ]),

            _buildSection(context, t('pp_s11_title'), Icons.mail_rounded, Colors.teal, [
              _buildParagraph(context, t('pp_s11_p1')),
              _buildBullet(context, t('pp_s11_b1')),
              _buildBullet(context, t('pp_s11_b2')),
            ]),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, IconData icon,
      Color color, List<Widget> children) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: color),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildParagraph(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              color: AppThemeColors.primaryText(context),
              height: 1.5)),
    );
  }

  Widget _buildBullet(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ',
              style: TextStyle(
                  color: AppColors.cyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13, color: AppThemeColors.primaryText(context))),
          ),
        ],
      ),
    );
  }
}
