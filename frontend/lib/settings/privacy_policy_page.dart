import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const String _lastUpdated = 'June 2025';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      appBar: AppBar(
        title: const Text(
          'Privacy Policy',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
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
                  const Text(
                    'Privacy Policy',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Last updated: $_lastUpdated',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'We are committed to protecting your personal information and your right to privacy.',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _buildSection('1. Information We Collect', Icons.storage_rounded,
                Colors.blue, [
              _buildParagraph(
                  'We collect information you provide directly to us when you:'),
              _buildBullet('Create an account (name, email, phone, address)'),
              _buildBullet('Complete your profile (gender, birthday, photo)'),
              _buildBullet('Record transactions with other users'),
              _buildBullet('Make payments or top-up your wallet'),
              _buildBullet('Contact support or submit feedback'),
              const SizedBox(height: 10),
              _buildParagraph('We also automatically collect:'),
              _buildBullet('Device information (device type, OS version)'),
              _buildBullet('IP address and location data'),
              _buildBullet(
                  'Usage data (features used, screens visited, session duration)'),
              _buildBullet('Transaction history and wallet activity'),
            ]),

            _buildSection(
                '2. How We Use Your Information', Icons.psychology_rounded,
                Colors.purple, [
              _buildParagraph('We use the information we collect to:'),
              _buildBullet('Create and manage your account'),
              _buildBullet('Process and record financial transactions'),
              _buildBullet('Send notifications about your account activity'),
              _buildBullet('Provide customer support'),
              _buildBullet('Improve and personalize the App experience'),
              _buildBullet('Detect and prevent fraud and abuse'),
              _buildBullet('Comply with legal obligations'),
              _buildBullet('Send promotional communications (with your consent)'),
            ]),

            _buildSection(
                '3. Information Sharing', Icons.share_rounded, Colors.orange, [
              _buildParagraph(
                  'We do not sell your personal information. We may share information in the following circumstances:'),
              _buildBullet(
                  'With other users: Your name and email are visible to users you transact with.'),
              _buildBullet(
                  'Service providers: Razorpay (payment processing), email delivery services.'),
              _buildBullet(
                  'Legal requirements: When required by law or to protect our rights.'),
              _buildBullet(
                  'Business transfers: In the event of a merger or acquisition.'),
              const SizedBox(height: 8),
              _buildParagraph(
                  'Your contact information is only shared based on your "Contact Sharing" privacy setting.'),
            ]),

            _buildSection(
                '4. Data Security', Icons.shield_rounded, Colors.green, [
              _buildParagraph(
                  'We implement industry-standard security measures to protect your information:'),
              _buildBullet('AES-256 encryption for data in transit (HTTPS)'),
              _buildBullet('bcrypt hashing for passwords'),
              _buildBullet('JWT tokens with short expiry periods'),
              _buildBullet('Regular security audits'),
              _buildBullet('Database access controls and monitoring'),
              const SizedBox(height: 8),
              _buildParagraph(
                  'While we strive to protect your information, no method of transmission over the internet is 100% secure.'),
            ]),

            _buildSection('5. Your Privacy Rights', Icons.person_rounded,
                const Color(0xFF00B4D8), [
              _buildParagraph('You have the following rights over your data:'),
              _buildBullet(
                  'Access: Request a copy of the personal data we hold about you.'),
              _buildBullet(
                  'Correction: Update inaccurate or incomplete information via your profile.'),
              _buildBullet(
                  'Deletion: Request deletion of your account and associated data.'),
              _buildBullet(
                  'Portability: Export your data via the Privacy Settings page.'),
              _buildBullet(
                  'Opt-out: Unsubscribe from marketing emails at any time.'),
              _buildBullet(
                  'Visibility: Control who can see your profile and contact information.'),
            ]),

            _buildSection(
                '6. Data Retention', Icons.history_rounded, Colors.brown, [
              _buildParagraph(
                  'We retain your personal data for as long as your account is active or as needed to provide services.'),
              _buildParagraph(
                  'Transaction records may be retained for up to 7 years for legal and accounting purposes, even after account deletion.'),
              _buildParagraph(
                  'When you deactivate your account, your personal profile data is preserved but your account is suspended. Permanent deletion may be requested by contacting support.'),
            ]),

            _buildSection('7. Cookies & Tracking', Icons.cookie_rounded,
                Colors.teal, [
              _buildParagraph(
                  'LenDen is a mobile application and does not use browser cookies. We use:'),
              _buildBullet(
                  'Secure device storage for authentication tokens and preferences.'),
              _buildBullet(
                  'Device identifiers to manage your active sessions and enable device management features.'),
              _buildBullet(
                  'Analytics data to understand App usage patterns (anonymized).'),
            ]),

            _buildSection('8. Children\'s Privacy', Icons.child_care_rounded,
                Colors.pink, [
              _buildParagraph(
                  'LenDen is not intended for children under 18 years of age. We do not knowingly collect personal information from children under 18.'),
              _buildParagraph(
                  'If you are a parent or guardian and believe your child has provided us with personal information, please contact us immediately.'),
            ]),

            _buildSection(
                '9. Third-Party Services', Icons.link_rounded, Colors.indigo, [
              _buildParagraph(
                  'Our App integrates with the following third-party services:'),
              _buildBullet(
                  'Razorpay: Payment processing. Subject to Razorpay\'s Privacy Policy.'),
              _buildBullet(
                  'Email providers: For sending OTPs, notifications, and account emails.'),
              _buildParagraph(
                  'These third parties have their own privacy policies and data practices which we do not control.'),
            ]),

            _buildSection(
                '10. Changes to This Policy', Icons.update_rounded, Colors.red,
                [
                  _buildParagraph(
                      'We may update this Privacy Policy from time to time. We will notify you of significant changes via the App.'),
                  _buildParagraph(
                      'Your continued use of LenDen after changes are posted constitutes your acceptance of the updated policy.'),
                ]),

            _buildSection('11. Contact Us', Icons.mail_rounded, Colors.teal, [
              _buildParagraph(
                  'If you have questions, concerns, or requests regarding this Privacy Policy or your personal data, please contact us through:'),
              _buildBullet('The Help & Support section in the App'),
              _buildBullet('Your registered email address'),
            ]),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
      String title, IconData icon, Color color, List<Widget> children) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
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

  Widget _buildParagraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13, color: Colors.black87, height: 1.5)),
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ',
              style: TextStyle(
                  color: Color(0xFF00B4D8),
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}
