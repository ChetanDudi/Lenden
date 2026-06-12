import 'package:flutter/material.dart';

class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  static const String _lastUpdated = 'June 2025';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      appBar: AppBar(
        title: const Text(
          'Terms of Service',
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
                  colors: [Color(0xFF00B4D8), Color(0xFF0096B4)],
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
                  const Text(
                    'Terms of Service',
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
                ],
              ),
            ),

            const SizedBox(height: 20),

            _buildSection('1. Acceptance of Terms', [
              'By accessing or using LenDen ("the App"), you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the App.',
              'These terms apply to all users of the App, including users who are also contributors of content, information, and other materials or services.',
            ]),

            _buildSection('2. Description of Service', [
              'LenDen is a peer-to-peer money management application that allows users to:',
              '• Record and track financial transactions with other users',
              '• Split group expenses among multiple participants',
              '• Manage a digital wallet for in-app payments',
              '• Make payments via integrated payment gateways',
              '• View analytics and history of financial activity',
            ]),

            _buildSection('3. User Accounts', [
              'You must create an account to use LenDen. You are responsible for maintaining the confidentiality of your account credentials.',
              'You agree to provide accurate, current, and complete information during registration and to update such information to keep it accurate.',
              'You are responsible for all activity that occurs under your account. Notify us immediately of any unauthorized use.',
              'Users must be at least 18 years of age to use LenDen.',
            ]),

            _buildSection('4. Financial Transactions', [
              'LenDen acts as a record-keeping and facilitation platform. We are not a bank or licensed financial institution.',
              'All transactions between users are the sole responsibility of the parties involved. LenDen does not guarantee that counterparties will fulfill their payment obligations.',
              'Wallet top-ups and payments are processed through Razorpay. By making payments, you agree to Razorpay\'s Terms of Service.',
              'You agree not to use LenDen for illegal transactions, money laundering, or any fraudulent activity.',
            ]),

            _buildSection('5. Wallet & Payments', [
              'The LenDen Wallet is an in-app balance that can be used for peer-to-peer payments and subscription purchases.',
              'Wallet balances are not insured or guaranteed by any government scheme.',
              'Withdrawals to bank accounts or UPI are subject to processing times and may require identity verification.',
              'In test mode, withdrawals are simulated and no actual funds are transferred.',
            ]),

            _buildSection('6. Prohibited Conduct', [
              'You agree not to:',
              '• Use the App for any unlawful purpose',
              '• Attempt to gain unauthorized access to any part of the App',
              '• Harass, abuse, or harm other users',
              '• Submit false or misleading transaction information',
              '• Reverse engineer, decompile, or disassemble the App',
              '• Use automated tools (bots, scrapers) against the App',
              '• Share your account credentials with third parties',
            ]),

            _buildSection('7. Privacy', [
              'Your privacy is important to us. Please review our Privacy Policy, which also governs your use of the App, to understand our practices.',
              'By using LenDen, you consent to the collection and use of your data as described in our Privacy Policy.',
            ]),

            _buildSection('8. Intellectual Property', [
              'The App and its original content, features, and functionality are owned by LenDen and are protected by applicable intellectual property laws.',
              'You may not reproduce, distribute, modify, or create derivative works from any part of the App without our explicit written permission.',
            ]),

            _buildSection('9. Subscription Plans', [
              'LenDen offers paid subscription plans that unlock additional features. Subscriptions are billed according to the plan selected.',
              'Subscriptions are non-refundable unless required by applicable law.',
              'We reserve the right to modify subscription pricing with reasonable advance notice.',
            ]),

            _buildSection('10. Termination', [
              'We may terminate or suspend your account at any time for violation of these Terms or for any other reason at our discretion.',
              'Upon termination, your right to use the App will immediately cease. Any outstanding transaction records will be retained as required by law.',
              'You may deactivate your account at any time through the Privacy Settings page, subject to clearing any outstanding financial obligations.',
            ]),

            _buildSection('11. Disclaimers', [
              'The App is provided "as is" and "as available" without warranties of any kind, either express or implied.',
              'We do not warrant that the App will be uninterrupted, error-free, or free of viruses or other harmful components.',
              'We are not responsible for any financial losses resulting from transactions between users.',
            ]),

            _buildSection('12. Limitation of Liability', [
              'To the maximum extent permitted by law, LenDen shall not be liable for any indirect, incidental, special, consequential, or punitive damages.',
              'Our total liability to you for any claims arising from your use of the App shall not exceed the amount you paid to us in the twelve months preceding the claim.',
            ]),

            _buildSection('13. Changes to Terms', [
              'We reserve the right to modify these Terms at any time. We will notify users of significant changes through the App.',
              'Your continued use of the App after changes are posted constitutes your acceptance of the modified Terms.',
            ]),

            _buildSection('14. Governing Law', [
              'These Terms shall be governed by and construed in accordance with the laws of India.',
              'Any disputes arising from these Terms shall be subject to the exclusive jurisdiction of the courts located in India.',
            ]),

            _buildSection('15. Contact Us', [
              'If you have questions about these Terms of Service, please contact us through the Help & Support section of the App.',
            ]),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<String> paragraphs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00B4D8),
                ),
              ),
              const SizedBox(height: 10),
              ...paragraphs.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      p,
                      style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
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
