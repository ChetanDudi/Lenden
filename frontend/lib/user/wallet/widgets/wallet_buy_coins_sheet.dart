import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../widgets/app_colors.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/currency_display.dart';
import '../../../utils/api_client.dart';
import '../../../utils/theme_helper.dart';

class WalletBuyCoinsSheet extends StatefulWidget {
  final double coinValue;
  final String coinCurrency;
  final double walletBalance;
  final DisplayCurrencyData? displayCurrencyData;
  final String initialDisplayCurrency;

  const WalletBuyCoinsSheet({
    super.key,
    required this.coinValue,
    required this.coinCurrency,
    required this.walletBalance,
    required this.displayCurrencyData,
    required this.initialDisplayCurrency,
  });

  @override
  State<WalletBuyCoinsSheet> createState() => _WalletBuyCoinsSheetState();
}

class _WalletBuyCoinsSheetState extends State<WalletBuyCoinsSheet>
    with CurrencyDisplayMixin<WalletBuyCoinsSheet> {
  late final TextEditingController _ctrl;
  bool _buying = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '10');
    loadCurrencies(
      seedData: widget.displayCurrencyData,
      seedCode: widget.initialDisplayCurrency,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int get _coins => int.tryParse(_ctrl.text.trim()) ?? 0;
  double get _baseCost => _coins * widget.coinValue;
  String get _totalCost => _baseCost.toStringAsFixed(2);
  bool get _canAfford => widget.walletBalance >= _baseCost;

  String get _displayCost => formatCurrencyAmount(
        _baseCost,
        from: widget.coinCurrency,
        to: selectedCurrency,
        data: currencyData,
      );

  String get _displayWalletBalance => formatCurrencyAmount(
        widget.walletBalance,
        from: 'INR',
        to: selectedCurrency,
        data: currencyData,
      );

  Future<void> _buy() async {
    if (_coins < 1 || !_canAfford) return;
    setState(() => _buying = true);
    try {
      final res = await ApiClient.post('/api/coins/buy-with-wallet',
          body: {'coinsToBuy': _coins});
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        if (mounted) {
          Navigator.of(context).pop(<String, dynamic>{
            'newWalletBalance': data['newWalletBalance'],
            'newCoinBalance': data['newCoinBalance'],
            'coins': _coins,
            'totalCost': _totalCost,
          });
        }
      } else {
        final err =
            (data['error'] ?? data['message'] ?? 'Purchase failed.').toString();
        if (mounted) showSnack(context, err, isError: true);
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coins = _coins;
    final totalCost = _totalCost;
    final canAfford = _canAfford;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppThemeColors.divider(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppThemeColors.tinted(context,
                        light: const Color(0xFFFFF8E1),
                        dark: const Color(0xFF3A2F12)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.monetization_on_rounded,
                      color: Color(0xFFD4A017), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Buy LenDen Coins',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppThemeColors.primaryText(context),
                          )),
                      Text(
                        '1 coin = ${widget.coinCurrency} ${widget.coinValue.toStringAsFixed(2)}  •  Wallet: $_displayWalletBalance',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppThemeColors.secondaryText(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context),
                ),
                decoration: InputDecoration(
                  suffixText: 'coins',
                  suffixStyle: TextStyle(
                      fontSize: 16,
                      color: AppThemeColors.secondaryText(context)),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.cyan)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppColors.cyan, width: 2)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [10, 25, 50, 100, 200].map((n) {
                  return ActionChip(
                    label: Text('+$n',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12)),
                    backgroundColor: AppColors.cyan.withValues(alpha: 0.10),
                    side: const BorderSide(color: AppColors.cyan),
                    onPressed: () {
                      _ctrl.text = '$n';
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              buildSheetCurrencySelector(),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context,
                      light: const Color(0xFFEAF5FF),
                      dark: const Color(0xFF1B3A4A)),
                  borderRadius: BorderRadius.circular(14),
                  border: canAfford ? null : Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total cost',
                        style: TextStyle(
                            color: AppThemeColors.secondaryText(context))),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_displayCost,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: canAfford ? AppColors.cyan : Colors.red,
                            )),
                        if (selectedCurrency.toUpperCase() !=
                            widget.coinCurrency.toUpperCase())
                          Text(
                            '${widget.coinCurrency} $totalCost',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppThemeColors.mutedText(context),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!canAfford && coins > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Insufficient wallet balance',
                  style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: (_buying || coins < 1 || !canAfford) ? null : _buy,
                  icon: _buying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.monetization_on_rounded),
                  label: Text(_buying
                      ? 'Buying…'
                      : 'Buy $coins Coin${coins == 1 ? '' : 's'}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4A017),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
