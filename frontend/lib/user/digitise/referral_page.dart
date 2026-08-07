import 'dart:convert';
import 'dart:ui';
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
    final grads = AppThemeColors.waveGradient(context);

    return Scaffold(
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [grads[0], grads[1]],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(top: -70, right: -70, child: _orb(220, 0.06)),
          Positioned(top: 120, left: -90, child: _orb(180, 0.045)),
          Positioned(top: 48, right: 28, child: _orb(68, 0.07)),
          SafeArea(
            child: _loading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : RefreshIndicator(
                  onRefresh: _fetchReferralInfo,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(children: [
                            _navBtn(Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)),
                            const Spacer(),
                            _navBtn(Icons.refresh_rounded, _fetchReferralInfo),
                          ]),
                        ),
                        const SizedBox(height: 4),
                        _buildHero(t),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _buildCodeCard(t),
                        ),
                        const SizedBox(height: 20),
                        _buildShareSection(t),
                        const SizedBox(height: 24),
                        _buildBottomSection(t),
                      ],
                    ),
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _orb(double size, double alpha) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: alpha),
    ),
  );

  Widget _navBtn(IconData icon, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: isDark ? 0.28 : 0.2),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.5 : 0.3)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildHero(Function(String) t) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        SizedBox(
          width: 112, height: 112,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 112, height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: isDark ? 0.09 : 0.11),
                ),
              ),
              Container(
                width: 84, height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: isDark ? 0.3 : 0.22),
                  border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.55 : 0.4), width: 2),
                  boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: isDark ? 0.18 : 0.28), blurRadius: 24, spreadRadius: 2)],
                ),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 44),
              ),
              Positioned(
                top: 4, right: 6,
                child: Icon(Icons.auto_awesome, color: Colors.white.withValues(alpha: 0.9), size: 16),
              ),
              Positioned(
                bottom: 10, left: 5,
                child: Icon(Icons.auto_awesome, color: Colors.white.withValues(alpha: 0.65), size: 10),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _rewardPill('+$_inviterRewardCoins', t('coins_label_short_lower'), t('you_get_label'), Colors.amber),
            const SizedBox(width: 10),
            Container(width: 1, height: 42, color: Colors.white.withValues(alpha: isDark ? 0.45 : 0.3)),
            const SizedBox(width: 10),
            _rewardPill('+$_refereeRewardCoins', t('coins_label_short_lower'), t('friend_gets_label'), AppColors.cyan),
          ],
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            t('refer_and_earn'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, height: 1.2),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Text(
            t('coins_awarded_after_signup_first_txn'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.8), height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _rewardPill(String amount, String unit, String label, Color accent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isDark ? 0.22 : 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.48 : 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.monetization_on_rounded, color: accent, size: 20),
          const SizedBox(width: 7),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$amount $unit', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 10, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeCard(Function(String) t) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.5 : 0.6),
            Colors.white.withValues(alpha: isDark ? 0.12 : 0.18),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(1.5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: isDark ? 0.18 : 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.qr_code_2, color: Colors.white.withValues(alpha: 0.75), size: 14),
                  const SizedBox(width: 6),
                  Text(
                    t('your_referral_code_label'),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          _referralCode.isNotEmpty ? _referralCode : '—',
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: _referralCode));
                        showSnack(context, t('code_copied'));
                      },
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 100),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            t('copy_label'),
                            style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShareSection(Function(String) t) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: isDark ? 0.35 : 0.25))),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  t('share_via_label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: isDark ? 0.35 : 0.25))),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_shareOptions.isEmpty)
          Text(t('no_share_options_configured'), style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: _shareOptions.map((opt) {
                final iconKey = (opt['icon'] ?? opt['key'] ?? '').toString();
                final label = (opt['label'] ?? 'Share').toString();
                final bg = _colorFor(iconKey);
                final icon = _iconFor(iconKey);
                final isLight = iconKey.toLowerCase() == 'snapchat';
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 18),
                  child: GestureDetector(
                    onTap: () => _shareVia(opt),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 58, height: 58,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: isDark ? 0.22 : 0.18),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.45 : 0.3), width: 1.5),
                            boxShadow: [BoxShadow(color: bg.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 3))],
                          ),
                          child: Icon(icon, color: isLight ? Colors.black87 : Colors.white, size: 24),
                        ),
                        const SizedBox(height: 7),
                        SizedBox(
                          width: 62,
                          child: Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomSection(Function(String) t) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppThemeColors.scaffoldBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: AppThemeColors.border(context), borderRadius: BorderRadius.circular(2)),
            ),
          ),

          Row(children: [
            Expanded(child: _statCard('$_totalShares', t('shares_label'), Icons.share_rounded, AppColors.cyan)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('$_invitedUsers', t('invited_label'), Icons.person_add_rounded, Colors.orange)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('$_convertedUsers', t('joined_label'), Icons.how_to_reg_rounded, const Color(0xFF48CAE4))),
          ]),
          const SizedBox(height: 14),

          _sectionCard(child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _coinBadge(t('you_get_label'), _inviterRewardCoins, Colors.amber),
              Container(width: 1, height: 84, color: AppThemeColors.divider(context)),
              _coinBadge(t('friend_gets_label'), _refereeRewardCoins, AppColors.cyan),
            ]),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppThemeColors.tinted(context, light: const Color(0xFFE0F7FA), dark: const Color(0xFF15333A)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                t('coins_awarded_after_signup_first_txn'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppThemeColors.tinted(context, light: const Color(0xFF006D77), dark: const Color(0xFF8FE3EE)),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ])),
          const SizedBox(height: 14),

          _sectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader(t('invite_link_label'), Icons.link_rounded, AppColors.cyan),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppThemeColors.scaffoldBg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppThemeColors.border(context)),
              ),
              child: Row(children: [
                Expanded(child: Text(_inviteLink, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: _inviteLink));
                    showSnack(context, t('link_copied'));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.copy_rounded, size: 13, color: AppColors.cyan),
                      const SizedBox(width: 4),
                      Text(t('copy_label'), style: const TextStyle(fontSize: 12, color: AppColors.cyan, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ]),
            ),
          ])),

          if (_recentShares.isNotEmpty) ...[
            const SizedBox(height: 14),
            _sectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _sectionHeader(t('recent_shares_label'), Icons.history_rounded, const Color(0xFF7C4DFF)),
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
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.18)),
                  ),
                  child: Row(children: [
                    Icon(_iconFor(ch), size: 15, color: color),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      '${ch.substring(0, 1).toUpperCase()}${ch.substring(1)} ${t('share_label')}',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: color),
                    )),
                    Text(stamp, style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 11)),
                  ]),
                );
              }),
            ])),
          ],

          const SizedBox(height: 14),
          _sectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader(t('how_it_works_label'), Icons.info_outline_rounded, AppColors.cyan),
            const SizedBox(height: 16),
            _step(1, t('step_share_referral_code'), AppColors.cyan),
            _step(2, t('step_friend_signs_up'), Colors.orange),
            _step(3, t('step_friend_first_transaction'), const Color(0xFF48CAE4)),
            _step(4, t('step_both_earn_coins'), Colors.amber, isLast: true),
          ])),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppThemeColors.cardBg(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppThemeColors.border(context)),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 2))],
    ),
    child: child,
  );

  Widget _sectionHeader(String title, IconData icon, Color color) => Row(children: [
    Container(
      width: 32, height: 32,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color, size: 16),
    ),
    const SizedBox(width: 10),
    Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppThemeColors.primaryText(context)))),
  ]);

  Widget _coinBadge(String label, int coins, Color color) {
    final t = AppLocalizations.of(context).t;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 120),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 66, height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.03)],
                  ),
                ),
              ),
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
                ),
                child: Icon(Icons.monetization_on_rounded, color: color, size: 26),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('+$coins', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          Text(t('coins_label_short_lower'), textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
            child: Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String value, String label, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 6),
            Text(value, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: AppThemeColors.secondaryText(context))),
          ]),
        ),
      ]),
    );
  }

  Widget _step(int num, String text, Color color, {bool isLast = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Center(child: Text('$num', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
            ),
            if (!isLast)
              Container(
                width: 2, height: 28,
                margin: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.4), color.withValues(alpha: 0.07)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 24, top: 9),
            child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppThemeColors.primaryText(context))),
          ),
        ),
      ],
    );
  }
}
