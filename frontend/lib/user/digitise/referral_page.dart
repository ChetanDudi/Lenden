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
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _logShare(String channel) async {
    try {
      await ApiClient.post('/api/referral/share', body: {'channel': channel, 'message': _message});
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
      _showSnack('Invite content copied!', success: true);
      return;
    }

    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null) { _showSnack('Invalid share URL'); return; }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched) {
      await _logShare(key);
      if (!mounted) return;
      _showSnack('Invite opened! Ask your friend to sign up.', success: true);
    } else {
      if (!mounted) return;
      _showSnack('Could not open ${option['label'] ?? 'the app'}. Make sure it is installed.');
    }
  }

  void _showSnack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green : Colors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
    ));
  }

  IconData _iconFor(String name) {
    switch (name.toLowerCase().trim()) {
      case 'whatsapp': return FontAwesomeIcons.whatsapp;
      case 'telegram': return FontAwesomeIcons.telegram;
      case 'email': case 'mail': return Icons.email_rounded;
      case 'sms': return Icons.sms_rounded;
      case 'copy': return Icons.copy_rounded;
      case 'facebook': return FontAwesomeIcons.facebook;
      case 'snapchat': return FontAwesomeIcons.snapchat;
      case 'instagram': return FontAwesomeIcons.instagram;
      case 'x': case 'twitter': return FontAwesomeIcons.twitter;
      case 'linkedin': return FontAwesomeIcons.linkedin;
      default: return Icons.share_rounded;
    }
  }

  Color _colorFor(String name) {
    switch (name.toLowerCase().trim()) {
      case 'whatsapp': return const Color(0xFF25D366);
      case 'telegram': return const Color(0xFF229ED9);
      case 'email': case 'mail': return const Color(0xFFFF7043);
      case 'sms': return const Color(0xFF26A69A);
      case 'copy': return const Color(0xFF5C6BC0);
      case 'facebook': case 'messenger': return const Color(0xFF1877F2);
      case 'snapchat': return const Color(0xFFFDD835);
      case 'instagram': return const Color(0xFFE1306C);
      case 'twitter': case 'x': return const Color(0xFF1DA1F2);
      case 'linkedin': return const Color(0xFF0A66C2);
      default: return const Color(0xFF607D8B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE0F7FA),
      body: Stack(
        children: [
          // Header gradient
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 200,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF00B4D8), Color(0xFF48CAE4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // App bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                    const Expanded(child: Text('Refer & Earn', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white))),
                    IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _fetchReferralInfo),
                  ]),
                ),

                Expanded(
                  child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _fetchReferralInfo,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                          children: [
                            // ── Reward coins hero ─────────────────────────
                            _triCard(
                              child: Container(
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                                child: Column(children: [
                                  // Coins display
                                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    _coinBadge('You Get', _inviterRewardCoins, Colors.amber),
                                    const SizedBox(width: 24),
                                    Container(width: 1, height: 60, color: Colors.grey[200]),
                                    const SizedBox(width: 24),
                                    _coinBadge('Friend Gets', _refereeRewardCoins, const Color(0xFF00B4D8)),
                                  ]),
                                  const SizedBox(height: 18),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0F7FA),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'Coins are awarded after your friend signs up and creates their first transaction',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 12, color: Color(0xFF006D77), fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // ── Stats row ─────────────────────────────────
                            Row(children: [
                              Expanded(child: _statCard('$_totalShares', 'Shares', Icons.share_rounded, const Color(0xFF00B4D8))),
                              const SizedBox(width: 10),
                              Expanded(child: _statCard('$_invitedUsers', 'Invited', Icons.person_add_rounded, Colors.orange)),
                              const SizedBox(width: 10),
                              Expanded(child: _statCard('$_convertedUsers', 'Joined', Icons.how_to_reg_rounded, const Color(0xFF48CAE4))),
                            ]),
                            const SizedBox(height: 14),

                            // ── Referral code card ────────────────────────
                            _triCard(
                              child: Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(children: [
                                      Icon(Icons.qr_code_2, color: Color(0xFF00B4D8), size: 20),
                                      SizedBox(width: 8),
                                      Text('Your Referral Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    ]),
                                    const SizedBox(height: 12),
                                    GestureDetector(
                                      onTap: () async {
                                        await Clipboard.setData(ClipboardData(text: _referralCode));
                                        _showSnack('Code copied!', success: true);
                                      },
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF0F9FF),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: const Color(0xFF00B4D8), width: 1.5, style: BorderStyle.solid),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Flexible(
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  _referralCode.isNotEmpty ? _referralCode : '—',
                                                  style: const TextStyle(
                                                    fontSize: 26, fontWeight: FontWeight.bold,
                                                    letterSpacing: 4, color: Color(0xFF00B4D8),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(color: const Color(0xFF00B4D8).withValues(alpha: 0.1), shape: BoxShape.circle),
                                              child: const Icon(Icons.copy_rounded, size: 18, color: Color(0xFF00B4D8)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text('Invite Link', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
                                    const SizedBox(height: 6),
                                    Row(children: [
                                      Expanded(
                                        child: Text(_inviteLink, style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                      GestureDetector(
                                        onTap: () async {
                                          await Clipboard.setData(ClipboardData(text: _inviteLink));
                                          _showSnack('Link copied!', success: true);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF00B4D8).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                            Icon(Icons.link, size: 14, color: Color(0xFF00B4D8)),
                                            SizedBox(width: 4),
                                            Text('Copy', style: TextStyle(fontSize: 12, color: Color(0xFF00B4D8), fontWeight: FontWeight.w600)),
                                          ]),
                                        ),
                                      ),
                                    ]),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // ── Share via ─────────────────────────────────
                            _triCard(
                              child: Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(children: [
                                      Icon(Icons.share_rounded, color: Color(0xFF00B4D8), size: 20),
                                      SizedBox(width: 8),
                                      Text('Share Via', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    ]),
                                    const SizedBox(height: 14),
                                    if (_shareOptions.isEmpty)
                                      Text('No share options configured.', style: TextStyle(color: Colors.grey[500]))
                                    else
                                      Wrap(
                                        spacing: 14, runSpacing: 14,
                                        children: _shareOptions.map((opt) {
                                          final iconKey = (opt['icon'] ?? opt['key'] ?? '').toString();
                                          final label = (opt['label'] ?? 'Share').toString();
                                          final bg = _colorFor(iconKey);
                                          final icon = _iconFor(iconKey);
                                          final isLight = iconKey.toLowerCase() == 'snapchat';
                                          return GestureDetector(
                                            onTap: () => _shareVia(opt),
                                            child: SizedBox(
                                              width: 68,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    width: 48, height: 48,
                                                    decoration: BoxDecoration(
                                                      color: bg,
                                                      shape: BoxShape.circle,
                                                      boxShadow: [BoxShadow(color: bg.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
                                                    ),
                                                    child: Icon(icon, color: isLight ? Colors.black : Colors.white, size: 22),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE0F7FA),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Text(
                                        'Ask your friend to sign up with your code and create at least one transaction.',
                                        style: TextStyle(fontSize: 12, color: Color(0xFF006D77), fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // ── Recent shares ─────────────────────────────
                            if (_recentShares.isNotEmpty)
                              _triCard(
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(children: [
                                        Icon(Icons.history, color: Color(0xFF00B4D8), size: 20),
                                        SizedBox(width: 8),
                                        Text('Recent Shares', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      ]),
                                      const SizedBox(height: 12),
                                      ..._recentShares.take(6).map((item) {
                                        final ch = (item['channel'] ?? 'other').toString();
                                        final at = (item['createdAt'] ?? '').toString();
                                        final stamp = at.length >= 10 ? at.substring(0, 10) : at;
                                        final color = _colorFor(ch);
                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.07),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: color.withValues(alpha: 0.2)),
                                          ),
                                          child: Row(children: [
                                            Icon(_iconFor(ch), size: 16, color: color),
                                            const SizedBox(width: 10),
                                            Expanded(child: Text(
                                              '${ch.substring(0, 1).toUpperCase()}${ch.substring(1)} Share',
                                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: color),
                                            )),
                                            Text(stamp, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                          ]),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ),

                            // ── How it works ──────────────────────────────
                            const SizedBox(height: 14),
                            _triCard(
                              child: Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(children: [
                                      Icon(Icons.info_outline, color: Color(0xFF00B4D8), size: 20),
                                      SizedBox(width: 8),
                                      Text('How it Works', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    ]),
                                    const SizedBox(height: 14),
                                    _step(1, 'Share your referral code or link with friends', Icons.share_rounded, const Color(0xFF00B4D8)),
                                    _step(2, 'Friend signs up on LenDen using your code', Icons.person_add_rounded, Colors.orange),
                                    _step(3, 'Friend creates their first transaction', Icons.receipt_long_rounded, const Color(0xFF48CAE4)),
                                    _step(4, 'Both of you earn LenDen coins!', Icons.monetization_on_rounded, Colors.amber, isLast: true),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _coinBadge(String label, int coins, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
          ),
          child: Center(
            child: Icon(Icons.monetization_on_rounded, color: color, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text('+$coins', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        Text('coins', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }

  Widget _statCard(String value, String label, IconData icon, Color color) {
    return _triCard(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]),
      ),
    );
  }

  Widget _step(int num, String text, IconData icon, Color color, {bool isLast = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 16),
            ),
            if (!isLast)
              Container(width: 2, height: 28, color: Colors.grey[200], margin: const EdgeInsets.symmetric(vertical: 2)),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 24, top: 6),
            child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }

  Widget _triCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: child,
    );
  }
}
