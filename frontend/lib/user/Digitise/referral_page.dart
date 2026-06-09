import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/api_client.dart';

class ReferralPage extends StatefulWidget {
  const ReferralPage({super.key});

  @override
  State<ReferralPage> createState() => _ReferralPageState();
}

class _ReferralPageState extends State<ReferralPage> {
  bool _loading = true;
  String _referralCode = '';
  String _inviteLink = '';
  String _message = '';
  int _totalShares = 0;
  int _invitedUsers = 0;
  int _convertedUsers = 0;
  int _inviterRewardCoins = 0;
  int _refereeRewardCoins = 0;
  List<dynamic> _recentShares = [];
  List<Map<String, dynamic>> _shareOptions = [];

  @override
  void initState() {
    super.initState();
    _fetchReferralInfo();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _fetchReferralInfo() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get('/api/referral/me');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final optionsRaw = List<dynamic>.from(data['shareOptions'] ?? []);
        setState(() {
          _referralCode = (data['referralCode'] ?? '').toString();
          _inviteLink = (data['inviteLink'] ?? '').toString();
          _message = (data['message'] ?? '').toString();
          _totalShares = _toInt(data['stats']?['totalShares']);
          _invitedUsers = _toInt(data['stats']?['invitedUsers']);
          _convertedUsers = _toInt(data['stats']?['convertedUsers']);
          _recentShares = List<dynamic>.from(data['stats']?['recentShares'] ?? []);
          _inviterRewardCoins = _toInt(data['rewards']?['inviterRewardCoins']);
          _refereeRewardCoins = _toInt(data['rewards']?['refereeRewardCoins']);
          _shareOptions = optionsRaw
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((e) => (e['key'] ?? '').toString().trim().isNotEmpty)
              .toList();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        _showInfoDialog(
          'Referral Info',
          'Unable to load referral details.',
          icon: Icons.error_outline,
          color: Colors.redAccent,
        );
      }
    } catch (_) {
      setState(() => _loading = false);
      _showInfoDialog(
        'Referral Info',
        'Network error while loading referral details.',
        icon: Icons.wifi_off,
        color: Colors.redAccent,
      );
    }
  }

  Future<void> _logShare(String channel) async {
    try {
      await ApiClient.post(
        '/api/referral/share',
        body: {'channel': channel, 'message': _message},
      );
    } catch (_) {}
  }

  Future<void> _shareVia(Map<String, dynamic> option) async {
    final key = (option['key'] ?? 'other').toString().toLowerCase();
    final template = (option['urlTemplate'] ?? '').toString().trim();
    if (template.isEmpty) return;

    final encodedMessage = Uri.encodeComponent(_message);
    final encodedInviteLink = Uri.encodeComponent(_inviteLink);
    final encodedSubject = Uri.encodeComponent('Join me on LenDen');

    final resolvedUrl = template
        .replaceAll('{message}', encodedMessage)
        .replaceAll('{inviteLink}', encodedInviteLink)
        .replaceAll('{subject}', encodedSubject);

    if (resolvedUrl.toLowerCase().startsWith('copy:')) {
      final rawCopy = template
          .replaceAll('{message}', _message)
          .replaceAll('{inviteLink}', _inviteLink)
          .replaceAll('{subject}', 'Join me on LenDen')
          .substring(5);
      await Clipboard.setData(ClipboardData(text: rawCopy));
      await _logShare(key);
      if (!mounted) return;
      _showInfoDialog(
        'Copied',
        'Invite content copied. Share it with your friends.',
        icon: Icons.copy,
        color: const Color(0xFF00B4D8),
      );
      return;
    }

    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null) {
      if (!mounted) return;
      _showInfoDialog(
        'Share Failed',
        'Invalid share URL for this option.',
        icon: Icons.error_outline,
        color: Colors.redAccent,
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched) {
      await _logShare(key);
      if (!mounted) return;
      _showInfoDialog(
        'Thanks for Referring',
        'Invite opened successfully. Ask your friend to sign up and create their first transaction.',
        icon: Icons.celebration_outlined,
        color: const Color(0xFF00B4D8),
      );
    } else {
      if (!mounted) return;
      _showInfoDialog(
        'Share Failed',
        'Could not open the selected app on this device.',
        icon: Icons.error_outline,
        color: Colors.redAccent,
      );
    }
  }

  IconData _iconFor(String name) {
    final key = name.toLowerCase().trim();
    switch (key) {
      case 'whatsapp':
        return FontAwesomeIcons.whatsapp;
      case 'telegram':
        return FontAwesomeIcons.telegram;
      case 'email':
      case 'mail':
        return Icons.email;
      case 'sms':
        return Icons.sms;
      case 'copy':
        return Icons.copy;
      case 'facebook':
        return FontAwesomeIcons.facebook;
      case 'snapchat':
        return FontAwesomeIcons.snapchat;
      case 'instagram':
        return FontAwesomeIcons.instagram;
      case 'x':
      case 'twitter':
        return FontAwesomeIcons.twitter;
      case 'linkedin':
        return FontAwesomeIcons.linkedin;
      case 'messenger':
        return Icons.message;
      default:
        return Icons.share;
    }
  }

  Color _buttonColorFor(String name) {
    final key = name.toLowerCase().trim();
    switch (key) {
      case 'whatsapp':
        return const Color(0xFF25D366);
      case 'telegram':
        return const Color(0xFF229ED9);
      case 'email':
      case 'mail':
        return const Color(0xFFFF7043);
      case 'sms':
        return const Color(0xFF26A69A);
      case 'copy':
        return const Color(0xFF5C6BC0);
      case 'facebook':
      case 'messenger':
        return const Color(0xFF1877F2);
      case 'snapchat':
        return const Color(0xFFFFFC00);
      case 'instagram':
        return const Color(0xFFE1306C);
      case 'twitter':
      case 'x':
        return const Color(0xFF1DA1F2);
      case 'linkedin':
        return const Color(0xFF0A66C2);
      default:
        return const Color(0xFF607D8B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FCFF),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: ReferralTopWaveClipper(),
              child: Container(
                height: 140,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00B4D8), Color(0xFF48CAE4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Refer & Earn',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                _triCard(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.share_rounded, size: 40, color: Color(0xFF00B4D8)),
                        const SizedBox(height: 10),
                        const Text(
                          'Invite friends to LenDen',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        _infoLine('Referral code', _referralCode),
                        const SizedBox(height: 8),
                        _infoLine('Total shares', '$_totalShares'),
                        const SizedBox(height: 8),
                        _infoLine('Invited users', '$_invitedUsers'),
                        const SizedBox(height: 8),
                        _infoLine('Converted users', '$_convertedUsers'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _triCard(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Colors.orange, Colors.white, Colors.green],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00B4D8).withOpacity(0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/icon.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(
                                    Icons.account_balance_wallet,
                                    color: Color(0xFF00B4D8),
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text('Invite Link', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        SelectableText(_inviteLink, style: TextStyle(color: Colors.grey[700])),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: _inviteLink));
                            if (!mounted) return;
                            _showInfoDialog(
                              'Copied',
                              'Invite link copied.',
                              icon: Icons.copy,
                              color: const Color(0xFF00B4D8),
                            );
                          },
                          icon: const Icon(Icons.link),
                          label: const Text('Copy Link'),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Reward rule: inviter gets $_inviterRewardCoins coins, new user gets $_refereeRewardCoins coins after first creation.',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1B4332),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _triCard(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Share via', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 10),
                        if (_shareOptions.isEmpty)
                          const Text('No share options configured.')
                        else
                          Wrap(
                            spacing: 16,
                            runSpacing: 14,
                            children: _shareOptions
                                .map(
                                  (opt) => _shareCircleButton(
                                    label: (opt['label'] ?? 'Share').toString(),
                                    iconKey: (opt['icon'] ?? opt['key'] ?? '').toString(),
                                    onTap: () => _shareVia(opt),
                                  ),
                                )
                                .toList(),
                          ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'After sharing, ask your friend to sign up with your code and create at least one quick, group, or user transaction.',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1B4332),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _triCard(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Recent Shares', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 8),
                        if (_recentShares.isEmpty)
                          const Text('No shares yet.')
                        else
                          ..._recentShares.take(6).map((item) {
                            final ch = (item['channel'] ?? 'other').toString();
                            final at = (item['createdAt'] ?? '').toString();
                            final stamp = at.length >= 10 ? at.substring(0, 10) : at;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(_iconFor(ch), size: 16, color: const Color(0xFF00B4D8)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${ch.toUpperCase()} share',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Text(stamp, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    return Row(
      children: [
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _shareCircleButton({
    required String label,
    required String iconKey,
    required VoidCallback onTap,
  }) {
    final bg = _buttonColorFor(iconKey);
    final icon = _iconFor(iconKey);
    final isSnapchat = iconKey.toLowerCase().trim() == 'snapchat';

    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: SizedBox(
        width: 78,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: bg.withOpacity(0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: isSnapchat ? Colors.black : Colors.white, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _triCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );
  }

  void _showInfoDialog(
    String title,
    String message, {
    required IconData icon,
    required Color color,
  }) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 42, color: color),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReferralTopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.4);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.5,
      size.width * 0.5,
      size.height * 0.4,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.3,
      size.width,
      size.height * 0.4,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
