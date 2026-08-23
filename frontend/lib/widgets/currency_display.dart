// Re-export so callers only need this one import for all currency utilities.
export '../utils/display_currency_helper.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_colors.dart';
import '../utils/theme_helper.dart';
import '../utils/display_currency_helper.dart';
import '../utils/currency_provider.dart';

/// Default currency list shown before the API response arrives.
const kCurrencyFallbacks = <Map<String, String>>[
  {'code': 'INR', 'symbol': '₹', 'label': 'Indian Rupee'},
  {'code': 'USD', 'symbol': '\$', 'label': 'US Dollar'},
  {'code': 'EUR', 'symbol': '€', 'label': 'Euro'},
  {'code': 'GBP', 'symbol': '£', 'label': 'British Pound'},
  {'code': 'JPY', 'symbol': '¥', 'label': 'Japanese Yen'},
  {'code': 'CAD', 'symbol': '\$', 'label': 'Canadian Dollar'},
  {'code': 'AUD', 'symbol': '\$', 'label': 'Australian Dollar'},
  {'code': 'CHF', 'symbol': 'Fr', 'label': 'Swiss Franc'},
];

/// Format [amount] (in [from] currency) as a display string in [to] currency.
/// Falls back gracefully to the original currency symbol when conversion data
/// is unavailable or the rate is missing.
String formatCurrencyAmount(
  num amount, {
  required String from,
  required String to,
  required DisplayCurrencyData? data,
  int decimals = 2,
}) {
  final src = from.toUpperCase();
  final tgt = to.toUpperCase();
  if (data == null || !data.canConvert(src, tgt)) {
    return '${currencySymbolFor(src)}${amount.toStringAsFixed(decimals)}';
  }
  final converted = data.convert(amount, src, tgt);
  return '${data.symbolFor(tgt)}${converted.toStringAsFixed(decimals)}';
}

/// Mixin for any `State<T>` that needs a currency selector and amount
/// formatting. Add `with CurrencyDisplayMixin<YourWidget>` to your State.
///
/// ```dart
/// class _MyPageState extends State<MyPage> with CurrencyDisplayMixin<MyPage> {
///   @override
///   void initState() {
///     super.initState();
///     loadCurrencies();
///   }
///   // Use formatAmount(amount), buildCurrencySelector(),
///   // or buildSheetCurrencySelector() in build().
/// }
/// ```
///
/// For sheet widgets that receive parent currency data, call:
///   `loadCurrencies(seedData: widget.displayCurrencyData, seedCode: widget.initialDisplayCurrency)`
mixin CurrencyDisplayMixin<T extends StatefulWidget> on State<T> {
  DisplayCurrencyData? _cData;
  String _cCode = 'INR';

  /// The loaded currency conversion data (null while loading or on error).
  DisplayCurrencyData? get currencyData => _cData;

  /// The currently selected display currency code (default from global setting).
  String get selectedCurrency => _cCode;

  /// Returns the global default currency from CurrencyProvider, or 'INR' as fallback.
  String _globalDefault() {
    try {
      return context.read<CurrencyProvider>().defaultCurrency;
    } catch (_) {
      return 'INR';
    }
  }

  /// Load supported currencies from the network.
  /// Pass [seedData] + [seedCode] to skip the network call — useful in sheet
  /// widgets that inherit data from their parent page.
  /// When [seedCode] is null, the global default currency from settings is used.
  Future<void> loadCurrencies({
    DisplayCurrencyData? seedData,
    String? seedCode,
    void Function(String? message)? onError,
  }) async {
    final effectiveCode = seedCode ?? _globalDefault();
    if (seedData != null) {
      if (!mounted) return;
      setState(() {
        _cData = seedData;
        _cCode = effectiveCode;
      });
      return;
    }
    if (mounted) setState(() => _cCode = effectiveCode);
    try {
      final data = await DisplayCurrencyHelper.load();
      if (!mounted) return;
      setState(() {
        _cData = data;
        if (!data.currencies.any((c) => c['code'] == _cCode)) {
          _cCode = _globalDefault();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cData = null;
        _cCode = _globalDefault();
      });
      onError?.call(null);
    }
  }

  /// Change the selected display currency and trigger a rebuild.
  void setCurrency(String code) => setState(() => _cCode = code);

  /// Format [amount] (in [from] currency) as a display string in [selectedCurrency].
  String formatAmount(num amount, {String from = 'INR', int decimals = 2}) =>
      formatCurrencyAmount(
        amount,
        from: from,
        to: _cCode,
        data: _cData,
        decimals: decimals,
      );

  List<Map<String, String>> get _currencyList =>
      _cData?.currencies ?? kCurrencyFallbacks;

  /// Full-sized tricolor-border dropdown for page-level currency selection
  /// (e.g. in history panel headers or tab headers).
  Widget buildCurrencySelector() => CurrencySelectorDropdown(
        currencies: _currencyList,
        value: _cCode,
        onChanged: setCurrency,
      );

  /// Compact "View in: [dropdown]" row for bottom sheets.
  Widget buildSheetCurrencySelector({String label = 'View in'}) =>
      CurrencySheetSelector(
        currencies: _currencyList,
        value: _cCode,
        label: label,
        onChanged: setCurrency,
      );
}

// ── Stateless widgets ────────────────────────────────────────────────────────

/// Full-sized tricolor-bordered currency dropdown.
/// Used as a page-level selector (history panels, tab headers, etc.).
class CurrencySelectorDropdown extends StatelessWidget {
  final List<Map<String, String>> currencies;
  final String value;
  final ValueChanged<String> onChanged;

  const CurrencySelectorDropdown({
    super.key,
    required this.currencies,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: AppColors.tricolorGradient,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            borderRadius: BorderRadius.circular(16),
            dropdownColor: AppThemeColors.cardBg(context),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            items: currencies
                .map((c) => DropdownMenuItem<String>(
                      value: c['code'],
                      child: Text(
                        '${c['symbol']} ${c['code']}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppThemeColors.primaryText(context),
                        ),
                      ),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }
}

/// Compact "View in: [dropdown]" currency row for bottom sheets.
class CurrencySheetSelector extends StatelessWidget {
  final List<Map<String, String>> currencies;
  final String value;
  final String label;
  final ValueChanged<String> onChanged;

  const CurrencySheetSelector({
    super.key,
    required this.currencies,
    required this.value,
    required this.onChanged,
    this.label = 'View in',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.swap_horiz_rounded,
            size: 14, color: AppThemeColors.mutedText(context)),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
              fontSize: 12, color: AppThemeColors.secondaryText(context)),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: AppColors.tricolorGradient,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(13),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isDense: true,
                borderRadius: BorderRadius.circular(14),
                dropdownColor: AppThemeColors.cardBg(context),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14),
                items: currencies
                    .map((c) => DropdownMenuItem<String>(
                          value: c['code'],
                          child: Text(
                            '${c['symbol']} ${c['code']}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppThemeColors.primaryText(context),
                            ),
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
