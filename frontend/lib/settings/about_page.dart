import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String _appVersion = '1.0.0';
  static const String _buildNumber = '100';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      appBar: AppBar(
        title: const Text(
          'About LenDen',
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
            // App identity card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00B4D8), Color(0xFF0096B4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00B4D8).withValues(alpha: 0.3),
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
                    'Smart Money Management',
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Version copied')),
                      );
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
              'What is LenDen?',
              Icons.info_outline_rounded,
              const Color(0xFF00B4D8),
              [
                _buildTextBlock(
                  'LenDen is a comprehensive peer-to-peer money management platform designed to simplify how you track, '
                  'settle, and manage financial transactions with friends, family, and colleagues.\n\n'
                  'Whether you\'re splitting a restaurant bill, tracking a loan to a friend, or managing group expenses '
                  'for a trip — LenDen has you covered.',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Core features
            _buildSection(
              'Core Features',
              Icons.star_rounded,
              Colors.orange,
              [
                _buildFeatureRow(Icons.swap_horiz_rounded, 'Quick Transactions',
                    'Instantly record who owes who with just an email and amount.'),
                _buildFeatureRow(Icons.lock_rounded, 'Secure Transactions',
                    'Formal lend/borrow records with digital acceptance and proof.'),
                _buildFeatureRow(Icons.group_rounded, 'Group Expenses',
                    'Add expenses to groups and split costs automatically.'),
                _buildFeatureRow(Icons.account_balance_wallet_rounded,
                    'LenDen Wallet',
                    'Top-up your wallet and pay directly via the app.'),
                _buildFeatureRow(Icons.credit_card_rounded, 'Razorpay Payments',
                    'Pay via card, UPI, or net banking through Razorpay.'),
                _buildFeatureRow(Icons.analytics_rounded, 'Analytics',
                    'Visual breakdown of your spending and lending habits.'),
                _buildFeatureRow(Icons.leaderboard_rounded, 'Leaderboard',
                    'See how you rank among friends in timely settlements.'),
                _buildFeatureRow(Icons.card_giftcard_rounded, 'Gift Cards',
                    'Send gift cards and rewards to your contacts.'),
              ],
            ),

            const SizedBox(height: 16),

            // Security & Privacy
            _buildSection(
              'Security & Privacy',
              Icons.shield_rounded,
              Colors.green,
              [
                _buildTextBlock(
                  'Your security is our top priority. LenDen uses industry-standard practices to protect your data:',
                ),
                const SizedBox(height: 8),
                _buildBullet('JWT-based authentication with auto token refresh'),
                _buildBullet('bcrypt password hashing (10 rounds)'),
                _buildBullet('HTTPS-only communication'),
                _buildBullet('MongoDB transactions for atomic wallet operations'),
                _buildBullet('Razorpay signature verification on all payments'),
                _buildBullet('OTP-verified alternative email changes'),
                _buildBullet('Device management and session control'),
              ],
            ),

            const SizedBox(height: 16),

            // Technology Stack
            _buildSection(
              'Built With',
              Icons.code_rounded,
              Colors.purple,
              [
                _buildTechRow('Flutter', 'Cross-platform mobile framework'),
                _buildTechRow('Node.js + Express', 'Backend API server'),
                _buildTechRow('MongoDB', 'Database with replica set'),
                _buildTechRow('Razorpay', 'Payment gateway'),
                _buildTechRow('Socket.io', 'Real-time chat & notifications'),
                _buildTechRow('JWT', 'Authentication tokens'),
                _buildTechRow('Nodemailer', 'Email delivery'),
              ],
            ),

            const SizedBox(height: 16),

            // Legal
            _buildSection(
              'Legal',
              Icons.gavel_rounded,
              Colors.blueGrey,
              [
                _buildLinkRow(context, 'Terms of Service',
                    Icons.description_outlined, '/terms'),
                _buildLinkRow(context, 'Privacy Policy',
                    Icons.privacy_tip_outlined, '/privacy'),
              ],
            ),

            const SizedBox(height: 16),

            // Made with love
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
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
                  const Text(
                    'Made with ❤️ in India',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '© ${DateTime.now().year} LenDen. All rights reserved.',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
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

  Widget _buildSection(
      String title, IconData icon, Color color, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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

  Widget _buildTextBlock(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ',
              style: TextStyle(
                  color: Color(0xFF00B4D8),
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, String subtitle) {
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
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
                Text(subtitle,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechRow(String name, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: Colors.purple, size: 16),
          const SizedBox(width: 10),
          Text(name,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87)),
          const SizedBox(width: 6),
          Expanded(
            child: Text('— $desc',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
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
          style: const TextStyle(
              fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: () => Navigator.pushNamed(context, route),
    );
  }
}
