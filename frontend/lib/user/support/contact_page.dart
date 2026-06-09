import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/api_client.dart';

class ContactPage extends StatefulWidget {
  const ContactPage({super.key});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _config = _fallbackConfig();

  @override
  void initState() {
    super.initState();
    _loadContactInfo();
  }

  static Map<String, dynamic> _fallbackConfig() => {
        'heroTitle': 'Contact Us',
        'heroDescription':
            'We would love to hear from you! Reach out to us through any of the following ways:',
        'email': {
          'label': 'Email',
          'value': 'chetandudi791@gmail.com',
          'url': 'mailto:chetandudi791@gmail.com',
          'enabled': true,
        },
        'facebook': {
          'label': 'Facebook',
          'value': 'Lenden App',
          'url': '',
          'enabled': true,
        },
        'whatsapp': {
          'label': 'WhatsApp',
          'value': '+91-XXXXXXXXXX',
          'url': '',
          'enabled': true,
        },
        'instagram': {
          'label': 'Instagram',
          'value': '_Chetan_Dudi',
          'url': '',
          'enabled': true,
        },
      };

  Future<void> _loadContactInfo() async {
    try {
      final response = await ApiClient.get('/api/contact-info');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _config = data;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load contact details.';
          _loading = false;
        });
      }
    } catch (_) {
      setState(() {
        _error = 'Network error while loading contact details.';
        _loading = false;
      });
    }
  }

  Future<void> _openChannel(Map<String, dynamic> channel, String fallback) async {
    final rawUrl = (channel['url'] ?? '').toString().trim();
    final value = (channel['value'] ?? '').toString().trim();
    final target = rawUrl.isNotEmpty ? rawUrl : '$fallback$value';
    if (target.trim().isEmpty) return;

    final uri = Uri.tryParse(target);
    if (uri == null) {
      _showMessage('Invalid contact link.');
      return;
    }

    final launched =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      _showMessage('Could not open this contact option.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  List<_ContactCardData> _buildChannels() {
    final entries = <_ContactCardData>[
      _ContactCardData(
        channel: Map<String, dynamic>.from(_config['email'] ?? {}),
        icon: Icons.email_outlined,
        tint: const Color(0xFF0096C7),
        fallbackPrefix: 'mailto:',
      ),
      _ContactCardData(
        channel: Map<String, dynamic>.from(_config['facebook'] ?? {}),
        icon: Icons.facebook_rounded,
        tint: const Color(0xFF1877F2),
        fallbackPrefix: 'https://facebook.com/',
      ),
      _ContactCardData(
        channel: Map<String, dynamic>.from(_config['whatsapp'] ?? {}),
        faIcon: FontAwesomeIcons.whatsapp,
        tint: const Color(0xFF25D366),
        fallbackPrefix: 'https://wa.me/',
      ),
      _ContactCardData(
        channel: Map<String, dynamic>.from(_config['instagram'] ?? {}),
        faIcon: FontAwesomeIcons.instagram,
        tint: const Color(0xFFE1306C),
        fallbackPrefix: 'https://instagram.com/',
      ),
    ];

    return entries
        .where((item) =>
            item.channel['enabled'] != false &&
            (item.channel['label'] ?? '').toString().trim().isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final channels = _buildChannels();

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Contact', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 260,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF003049), Color(0xFF00B4D8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned(
            top: 140,
            right: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF00B4D8),
                                      Color(0xFF90E0EF),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                padding: const EdgeInsets.all(18),
                                child: Image.asset(
                                  'assets/icon.png',
                                  width: 72,
                                  height: 72,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(
                                    Icons.support_agent_rounded,
                                    size: 60,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                (_config['heroTitle'] ?? 'Contact Us')
                                    .toString(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0B1F33),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                (_config['heroDescription'] ?? '').toString(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.5,
                                  color: Colors.blueGrey.shade600,
                                ),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFB3261E),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        ...channels.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _ContactCard(
                                data: item,
                                onTap: () => _openChannel(
                                  item.channel,
                                  item.fallbackPrefix,
                                ),
                              ),
                            )),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Back'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF003049),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ContactCardData {
  final Map<String, dynamic> channel;
  final IconData? icon;
  final IconData? faIcon;
  final Color tint;
  final String fallbackPrefix;

  _ContactCardData({
    required this.channel,
    this.icon,
    this.faIcon,
    required this.tint,
    required this.fallbackPrefix,
  });
}

class _ContactCard extends StatelessWidget {
  final _ContactCardData data;
  final VoidCallback onTap;

  const _ContactCard({
    required this.data,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = (data.channel['label'] ?? '').toString();
    final value = (data.channel['value'] ?? '').toString();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: data.tint.withOpacity(0.16)),
            boxShadow: [
              BoxShadow(
                color: data.tint.withOpacity(0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: data.tint.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: data.faIcon != null
                    ? FaIcon(data.faIcon, color: data.tint)
                    : Icon(data.icon, color: data.tint),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blueGrey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, color: data.tint),
            ],
          ),
        ),
      ),
    );
  }
}
