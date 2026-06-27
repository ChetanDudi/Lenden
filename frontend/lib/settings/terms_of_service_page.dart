import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  static const String _lastUpdated = 'June 2025';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: t('terms_of_service')),
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
                  colors: [AppColors.cyan, Color(0xFF0096B4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(Icons.description_rounded,
                      color: Colors.white, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    t('terms_of_service'),
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${t('tos_last_updated_prefix')} $_lastUpdated',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _buildSection(context, t('tos_s1_title'),
                [t('tos_s1_p1'), t('tos_s1_p2')]),

            _buildSection(context, t('tos_s2_title'), [
              t('tos_s2_p1'),
              t('tos_s2_p2'),
              t('tos_s2_p3'),
              t('tos_s2_p4'),
              t('tos_s2_p5'),
              t('tos_s2_p6'),
            ]),

            _buildSection(context, t('tos_s3_title'), [
              t('tos_s3_p1'),
              t('tos_s3_p2'),
              t('tos_s3_p3'),
              t('tos_s3_p4'),
            ]),

            _buildSection(context, t('tos_s4_title'), [
              t('tos_s4_p1'),
              t('tos_s4_p2'),
              t('tos_s4_p3'),
              t('tos_s4_p4'),
            ]),

            _buildSection(context, t('tos_s5_title'), [
              t('tos_s5_p1'),
              t('tos_s5_p2'),
              t('tos_s5_p3'),
              t('tos_s5_p4'),
            ]),

            _buildSection(context, t('tos_s6_title'), [
              t('tos_s6_p1'),
              t('tos_s6_p2'),
              t('tos_s6_p3'),
              t('tos_s6_p4'),
              t('tos_s6_p5'),
              t('tos_s6_p6'),
              t('tos_s6_p7'),
              t('tos_s6_p8'),
            ]),

            _buildSection(context, t('tos_s7_title'),
                [t('tos_s7_p1'), t('tos_s7_p2')]),

            _buildSection(context, t('tos_s8_title'),
                [t('tos_s8_p1'), t('tos_s8_p2')]),

            _buildSection(context, t('tos_s9_title'), [
              t('tos_s9_p1'),
              t('tos_s9_p2'),
              t('tos_s9_p3'),
            ]),

            _buildSection(context, t('tos_s10_title'), [
              t('tos_s10_p1'),
              t('tos_s10_p2'),
              t('tos_s10_p3'),
            ]),

            _buildSection(context, t('tos_s11_title'), [
              t('tos_s11_p1'),
              t('tos_s11_p2'),
              t('tos_s11_p3'),
            ]),

            _buildSection(context, t('tos_s12_title'),
                [t('tos_s12_p1'), t('tos_s12_p2')]),

            _buildSection(context, t('tos_s13_title'),
                [t('tos_s13_p1'), t('tos_s13_p2')]),

            _buildSection(context, t('tos_s14_title'),
                [t('tos_s14_p1'), t('tos_s14_p2')]),

            _buildSection(context, t('tos_s15_title'), [t('tos_s15_p1')]),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, String title, List<String> paragraphs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.cyan,
                ),
              ),
              const SizedBox(height: 10),
              ...paragraphs.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      p,
                      style: TextStyle(
                          fontSize: 13,
                          color: AppThemeColors.primaryText(context),
                          height: 1.5),
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
