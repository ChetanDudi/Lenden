import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';

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
    final t = AppLocalizations.of(context).t;
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
      showSnack(context, t('invite_content_copied'));
      return;
    }

    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null) { showSnack(context, t('invalid_share_url'), isError: true); return; }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched) {
      await _logShare(key);
      if (!mounted) return;
      showSnack(context, t('invite_opened_ask_friend'));
    } else {
      if (!mounted) return;
      showSnack(context, '${t('could_not_open_app_prefix')} ${option['label'] ?? t('the_app_label')}. ${t('make_sure_installed_suffix')}', isError: true);
    }
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
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          // Header gradient
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: AppThemeColors.waveGradient(context),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
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
                    IconButton(icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)), onPressed: () => Navigator.pop(context)),
                    Expanded(child: Text(t('refer_and_earn'), textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)))),
                    IconButton(icon: Icon(Icons.refresh, color: AppThemeColors.primaryText(context)), onPressed: _fetchReferralInfo),
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
                                decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(18)),
                                child: Column(children: [
                                  // Coins display
                                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    _coinBadge(t('you_get_label'), _inviterRewardCoins, Colors.amber),
                                    const SizedBox(width: 24),
                                    Container(width: 1, height: 60, color: AppThemeColors.divider(context)),
                                    const SizedBox(width: 24),
                                    _coinBadge(t('friend_gets_label'), _refereeRewardCoins, AppColors.cyan),
                                  ]),
                                  const SizedBox(height: 18),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppThemeColors.tinted(context, light: const Color(0xFFE0F7FA), dark: const Color(0xFF15333A)),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      t('coins_awarded_after_signup_first_txn'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 12, color: AppThemeColors.tinted(context, light: const Color(0xFF006D77), dark: const Color(0xFF8FE3EE)), fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // ── Stats row ─────────────────────────────────
                            Row(children: [
                              Expanded(child: _statCard('$_totalShares', t('shares_label'), Icons.share_rounded, AppColors.cyan)),
                              const SizedBox(width: 10),
                              Expanded(child: _statCard('$_invitedUsers', t('invited_label'), Icons.person_add_rounded, Colors.orange)),
                              const SizedBox(width: 10),
                              Expanded(child: _statCard('$_convertedUsers', t('joined_label'), Icons.how_to_reg_rounded, const Color(0xFF48CAE4))),
                            ]),
                            const SizedBox(height: 14),

                            // ── Referral code card ────────────────────────
                            _triCard(
                              child: Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(18)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      const Icon(Icons.qr_code_2, color: AppColors.cyan, size: 20),
                                      const SizedBox(width: 8),
                                      Text(t('your_referral_code_label'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppThemeColors.primaryText(context))),
                                    ]),
                                    const SizedBox(height: 12),
                                    GestureDetector(
                                      onTap: () async {
                                        await Clipboard.setData(ClipboardData(text: _referralCode));
                                        showSnack(context, t('code_copied'));
                                      },
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                                        decoration: BoxDecoration(
                                          color: AppThemeColors.tinted(context, light: const Color(0xFFF0F9FF), dark: const Color(0xFF132A33)),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: AppColors.cyan, width: 1.5, style: BorderStyle.solid),
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
                                                    letterSpacing: 4, color: AppColors.cyan,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.1), shape: BoxShape.circle),
                                              child: const Icon(Icons.copy_rounded, size: 18, color: AppColors.cyan),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(t('invite_link_label'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppThemeColors.secondaryText(context))),
                                    const SizedBox(height: 6),
                                    Row(children: [
                                      Expanded(
                                        child: Text(_inviteLink, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                      GestureDetector(
                                        onTap: () async {
                                          await Clipboard.setData(ClipboardData(text: _inviteLink));
                                          showSnack(context, t('link_copied'));
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                          decoration: BoxDecoration(
                                            color: AppColors.cyan.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                                            const Icon(Icons.link, size: 14, color: AppColors.cyan),
                                            const SizedBox(width: 4),
                                            Text(t('copy_label'), style: const TextStyle(fontSize: 12, color: AppColors.cyan, fontWeight: FontWeight.w600)),
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
                                decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(18)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      const Icon(Icons.share_rounded, color: AppColors.cyan, size: 20),
                                      const SizedBox(width: 8),
                                      Text(t('share_via_label'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppThemeColors.primaryText(context))),
                                    ]),
                                    const SizedBox(height: 14),
                                    if (_shareOptions.isEmpty)
                                      Text(t('no_share_options_configured'), style: TextStyle(color: AppThemeColors.mutedText(context)))
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
                                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context))),
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
                                        color: AppThemeColors.tinted(context, light: const Color(0xFFE0F7FA), dark: const Color(0xFF15333A)),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        t('ask_friend_signup_create_txn'),
                                        style: TextStyle(fontSize: 12, color: AppThemeColors.tinted(context, light: const Color(0xFF006D77), dark: const Color(0xFF8FE3EE)), fontWeight: FontWeight.w500),
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
                                  decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(18)),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        const Icon(Icons.history, color: AppColors.cyan, size: 20),
                                        const SizedBox(width: 8),
                                        Text(t('recent_shares_label'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppThemeColors.primaryText(context))),
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
                                              '${ch.substring(0, 1).toUpperCase()}${ch.substring(1)} ${t('share_label')}',
                                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: color),
                                            )),
                                            Text(stamp, style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 12)),
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
                                decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(18)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      const Icon(Icons.info_outline, color: AppColors.cyan, size: 20),
                                      const SizedBox(width: 8),
                                      Text(t('how_it_works_label'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppThemeColors.primaryText(context))),
                                    ]),
                                    const SizedBox(height: 14),
                                    _step(1, t('step_share_referral_code'), Icons.share_rounded, AppColors.cyan),
                                    _step(2, t('step_friend_signs_up'), Icons.person_add_rounded, Colors.orange),
                                    _step(3, t('step_friend_first_transaction'), Icons.receipt_long_rounded, const Color(0xFF48CAE4)),
                                    _step(4, t('step_both_earn_coins'), Icons.monetization_on_rounded, Colors.amber, isLast: true),
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
        Text(label, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
        Text(AppLocalizations.of(context).t('coins_label_short_lower'), style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
      ],
    );
  }

  Widget _statCard(String value, String label, IconData icon, Color color) {
    return _triCard(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
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
              Container(width: 2, height: 28, color: AppThemeColors.divider(context), margin: const EdgeInsets.symmetric(vertical: 2)),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 24, top: 6),
            child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppThemeColors.primaryText(context))),
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
