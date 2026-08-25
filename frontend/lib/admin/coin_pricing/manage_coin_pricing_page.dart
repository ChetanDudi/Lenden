import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive.dart';
import '../widgets/top_wave_clipper.dart';

// ─── Entry descriptors ───────────────────────────────────────────────────────

class _CoinEntry {
  final String key;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isEarn;

  const _CoinEntry({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isEarn,
  });
}

const _spendEntries = [
  _CoinEntry(
    key: 'privateChatMessageCost',
    label: 'Private Chat Message',
    subtitle: 'Per message after free limit',
    icon: Icons.chat_bubble_outline_rounded,
    color: Color(0xFF1565C0),
    isEarn: false,
  ),
  _CoinEntry(
    key: 'groupChatMessageCost',
    label: 'Group Chat Message',
    subtitle: 'Per message in group chats',
    icon: Icons.forum_outlined,
    color: Color(0xFF6A1B9A),
    isEarn: false,
  ),
  _CoinEntry(
    key: 'quickTransactionCost',
    label: 'Quick Transaction',
    subtitle: 'After free quota',
    icon: Icons.flash_on_rounded,
    color: Color(0xFF1A56DB),
    isEarn: false,
  ),
  _CoinEntry(
    key: 'secureTransactionCost',
    label: 'Secure Transaction',
    subtitle: 'After free quota',
    icon: Icons.lock_outline_rounded,
    color: Color(0xFF1E6B3B),
    isEarn: false,
  ),
  _CoinEntry(
    key: 'groupCreationCost',
    label: 'Group Creation',
    subtitle: 'After daily limit',
    icon: Icons.group_add_outlined,
    color: Color(0xFF8B7A30),
    isEarn: false,
  ),
  _CoinEntry(
    key: 'groupExpenseCost',
    label: 'Group Expense',
    subtitle: 'After daily limit',
    icon: Icons.receipt_long_outlined,
    color: Color(0xFF9B5B21),
    isEarn: false,
  ),
  _CoinEntry(
    key: 'communityCoinCost',
    label: 'Community Creation',
    subtitle: 'Beyond free community limit',
    icon: Icons.hub_outlined,
    color: Color(0xFF00838F),
    isEarn: false,
  ),
];

const _earnEntries = [
  _CoinEntry(
    key: 'dailyLoginReward',
    label: 'Daily Login',
    subtitle: 'Earned each day on login',
    icon: Icons.login_rounded,
    color: Color(0xFF2E7D32),
    isEarn: true,
  ),
  _CoinEntry(
    key: 'leaderboardRank1Reward',
    label: 'Leaderboard Rank #1',
    subtitle: 'Monthly leaderboard winner',
    icon: Icons.workspace_premium_rounded,
    color: Color(0xFFF9A825),
    isEarn: true,
  ),
  _CoinEntry(
    key: 'leaderboardRank2Reward',
    label: 'Leaderboard Rank #2',
    subtitle: 'Monthly leaderboard runner-up',
    icon: Icons.emoji_events_outlined,
    color: Color(0xFF78909C),
    isEarn: true,
  ),
  _CoinEntry(
    key: 'leaderboardRank3Reward',
    label: 'Leaderboard Rank #3',
    subtitle: 'Monthly leaderboard third place',
    icon: Icons.emoji_events_outlined,
    color: Color(0xFFBF8040),
    isEarn: true,
  ),
];

// ─── Page ────────────────────────────────────────────────────────────────────

class ManageCoinPricingPage extends StatefulWidget {
  const ManageCoinPricingPage({super.key});

  @override
  State<ManageCoinPricingPage> createState() => _ManageCoinPricingPageState();
}

class _ManageCoinPricingPageState extends State<ManageCoinPricingPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final Map<String, TextEditingController> _controllers = {};
  final _coinValueController = TextEditingController();
  String _coinValueCurrency = 'INR';
  String _displayCurrency = 'INR';

  List<Map<String, dynamic>> _currencies = [];
  Map<String, double> _rateMap = {};

  @override
  void initState() {
    super.initState();
    for (final e in [..._spendEntries, ..._earnEntries]) {
      _controllers[e.key] = TextEditingController();
    }
    _loadConfig();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    _coinValueController.dispose();
    super.dispose();
  }

  // ── Network ──────────────────────────────────────────────────────────────

  Future<void> _loadConfig() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get('/api/admin/coin-pricing');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final config = data['config'] as Map<String, dynamic>? ?? {};
        final currencies = (data['currencies'] as List?)
                ?.cast<Map<String, dynamic>>() ?? [];
        final rateMap = (data['rateMap'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, (v as num).toDouble()));

        setState(() {
          for (final e in [..._spendEntries, ..._earnEntries]) {
            _controllers[e.key]!.text =
                (config[e.key] as num? ?? 0).toInt().toString();
          }
          _coinValueController.text =
              (config['coinValue'] as num? ?? 0.10).toString();
          _coinValueCurrency =
              (config['coinValueCurrency'] as String?) ?? 'INR';
          _currencies = currencies;
          _rateMap = rateMap;
          _displayCurrency = _coinValueCurrency;
          _loading = false;
        });
      } else {
        final data = res.body.isNotEmpty
            ? jsonDecode(res.body) as Map<String, dynamic>
            : {};
        setState(() {
          _error = (data['error'] ?? 'Failed to load coin pricing.').toString();
          _loading = false;
        });
      }
    } catch (e) {
      setState(() { _error = 'Error: $e'; _loading = false; });
    }
  }

  Future<void> _save() async {
    final body = <String, dynamic>{};
    for (final e in [..._spendEntries, ..._earnEntries]) {
      final val = int.tryParse(_controllers[e.key]!.text.trim());
      if (val == null || val < 0) {
        _msg('"${e.label}" must be a non-negative integer.', isError: true);
        return;
      }
      body[e.key] = val;
    }
    final coinVal = double.tryParse(_coinValueController.text.trim());
    if (coinVal == null || coinVal < 0) {
      _msg('Coin value must be a non-negative number.', isError: true);
      return;
    }
    body['coinValue'] = coinVal;
    body['coinValueCurrency'] = _coinValueCurrency;

    setState(() => _saving = true);
    try {
      final res = await ApiClient.put('/api/admin/coin-pricing', body: body);
      setState(() => _saving = false);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        _msg('Coin pricing saved successfully.');
        await _loadConfig();
      } else {
        final data = res.body.isNotEmpty
            ? jsonDecode(res.body) as Map<String, dynamic>
            : {};
        _msg((data['error'] ?? 'Failed to save.').toString(), isError: true);
      }
    } catch (e) {
      setState(() => _saving = false);
      _msg('Error saving: $e', isError: true);
    }
  }

  void _msg(String m, {bool isError = false}) {
    if (mounted) showSnack(context, m, isError: isError);
  }

  // ── Currency conversion display ───────────────────────────────────────────

  String _equiv(int coins) {
    final coinVal =
        double.tryParse(_coinValueController.text.trim()) ?? 0.10;
    final baseAmount = coins * coinVal;

    final displayAmount = _displayCurrency == _coinValueCurrency
        ? baseAmount
        : baseAmount * (_rateMap[_displayCurrency] ?? 1.0);

    final sym = _currencies
        .firstWhere(
          (c) => c['code'] == _displayCurrency,
          orElse: () => {'symbol': _displayCurrency},
        )['symbol']
        ?.toString() ??
        _displayCurrency;

    return '$sym${displayAmount.toStringAsFixed(2)}';
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Tricolor-border card — same pattern as referral settings page.
  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      ),
    );
  }

  Widget _sectionLabel(String title, String subtitle, IconData icon,
      Color iconColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppThemeColors.primaryText(context),
                    )),
                Text(subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppThemeColors.secondaryText(context),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          // Top wave — exact pattern from all other admin pages
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: context.sh(156),
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Header row
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back,
                            color: AppThemeColors.primaryText(context)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            'Coin Pricing',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppThemeColors.primaryText(context),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),

                // Body
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? _buildError()
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                              children: [
                                _buildCoinValueCard(),
                                const SizedBox(height: 14),
                                _buildCurrencySelector(),
                                const SizedBox(height: 20),
                                _buildSection(
                                  title: 'Spend Costs',
                                  subtitle: 'Coins deducted per action',
                                  icon: Icons.remove_circle_outline_rounded,
                                  iconColor: Colors.redAccent,
                                  entries: _spendEntries,
                                ),
                                const SizedBox(height: 20),
                                _buildSection(
                                  title: 'Earn Rewards',
                                  subtitle: 'Coins awarded to users',
                                  icon: Icons.add_circle_outline_rounded,
                                  iconColor: const Color(0xFF2E7D32),
                                  entries: _earnEntries,
                                ),
                                const SizedBox(height: 24),
                                _buildSaveButton(),
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

  Widget _buildError() {
    return errorStateWidget(context, _error!, _loadConfig);
  }

  // ── Coin value card ───────────────────────────────────────────────────────

  Widget _buildCoinValueCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.monetization_on_rounded,
                    color: Color(0xFFD4A017), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Coin Real-Money Value',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppThemeColors.primaryText(context),
                        )),
                    Text('Approximate real-world value of 1 LenDen coin',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppThemeColors.secondaryText(context),
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('1 Coin  =',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppThemeColors.primaryText(context),
                  )),
              const SizedBox(width: 10),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _coinValueController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,6}$')),
                  ],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppThemeColors.primaryText(context),
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: AppThemeColors.border(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: AppColors.cyan, width: 1.8),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              if (_currencies.isEmpty)
                Text(_coinValueCurrency,
                    style: const TextStyle(fontWeight: FontWeight.w700))
              else
                DropdownButton<String>(
                  value: _currencies.any(
                          (c) => c['code'] == _coinValueCurrency)
                      ? _coinValueCurrency
                      : _currencies.first['code']?.toString(),
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(12),
                  dropdownColor: AppThemeColors.cardBg(context),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppThemeColors.primaryText(context),
                  ),
                  items: _currencies
                      .map((c) => DropdownMenuItem<String>(
                            value: c['code']?.toString() ?? '',
                            child: Text(
                                '${c['code']} ${c['symbol']}'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _coinValueCurrency = v);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Currency selector chips ───────────────────────────────────────────────

  Widget _buildCurrencySelector() {
    if (_currencies.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'View equivalents in',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppThemeColors.secondaryText(context),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _currencies.map((c) {
            final code = c['code']?.toString() ?? '';
            final sym = c['symbol']?.toString() ?? code;
            return ChoiceChip(
              label: Text('$sym $code'),
              selected: _displayCurrency == code,
              onSelected: (_) => setState(() => _displayCurrency = code),
              selectedColor: AppThemeColors.tinted(context,
                  light: const Color(0xFFEAF5FF),
                  dark: const Color(0xFF1B3A4A)),
              labelStyle: TextStyle(
                color: _displayCurrency == code
                    ? AppColors.cyan
                    : AppThemeColors.primaryText(context),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Section (spend / earn) ────────────────────────────────────────────────

  Widget _buildSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required List<_CoinEntry> entries,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(title, subtitle, icon, iconColor),
        ...entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildRow(e),
            )),
      ],
    );
  }

  Widget _buildRow(_CoinEntry e) {
    final ctrl = _controllers[e.key]!;
    final coins = int.tryParse(ctrl.text.trim()) ?? 0;
    final equiv = _equiv(coins);
    final accentColor = e.isEarn ? const Color(0xFF2E7D32) : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            e.color.withValues(alpha: 0.5),
            AppThemeColors.cardBg(context),
            e.color.withValues(alpha: 0.2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Icon badge
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: e.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(e.icon, color: e.color, size: 18),
            ),
            const SizedBox(width: 10),
            // Label + equivalent
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppThemeColors.primaryText(context),
                      )),
                  Text(e.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppThemeColors.secondaryText(context),
                      )),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.monetization_on_rounded,
                          size: 11, color: Color(0xFFD4A017)),
                      const SizedBox(width: 3),
                      Text(
                        '≈ $equiv',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFD4A017),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Coin input
            SizedBox(
              width: 68,
              child: Column(
                children: [
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: accentColor,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: accentColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: accentColor.withValues(alpha: 0.35)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: accentColor, width: 1.8),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.isEarn ? '+coins' : 'coins',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: accentColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Save button ───────────────────────────────────────────────────────────

  Widget _buildSaveButton() {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.save_rounded),
        label: Text(_saving ? 'Saving…' : 'Save Coin Pricing'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cyan,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
