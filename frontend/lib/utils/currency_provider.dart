import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CurrencyProvider extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _kKey = 'default_display_currency';

  String _defaultCurrency = 'INR';
  String get defaultCurrency => _defaultCurrency;

  Future<void> load() async {
    try {
      final stored = await _storage.read(key: _kKey);
      if (stored != null && stored.isNotEmpty) {
        _defaultCurrency = stored;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setDefaultCurrency(String code) async {
    if (_defaultCurrency == code) return;
    _defaultCurrency = code;
    try {
      await _storage.write(key: _kKey, value: code);
    } catch (_) {}
    notifyListeners();
  }

  /// Show a stylish currency picker bottom sheet.
  static void showPickerSheet(
    BuildContext context, {
    required List<Map<String, String>> currencies,
    required String selected,
    required void Function(String code) onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _CurrencyPickerSheet(
        currencies: currencies,
        selected: selected,
        onSelect: (code) {
          onSelect(code);
          Navigator.pop(ctx);
        },
      ),
    );
  }
}

class _CurrencyPickerSheet extends StatelessWidget {
  final List<Map<String, String>> currencies;
  final String selected;
  final void Function(String code) onSelect;

  const _CurrencyPickerSheet({
    required this.currencies,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: _divider(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00B4D8), Color(0xFF0077B6)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.currency_exchange_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Select Currency',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _primaryText(context))),
                Text('Choose display currency', style: TextStyle(fontSize: 12, color: _secondaryText(context))),
              ])),
            ]),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: currencies.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final c = currencies[i];
                final isSel = c['code'] == selected;
                return GestureDetector(
                  onTap: () => onSelect(c['code']!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSel
                          ? const Color(0xFF00B4D8).withValues(alpha: 0.08)
                          : _surfaceBg(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSel
                            ? const Color(0xFF00B4D8).withValues(alpha: 0.5)
                            : _border(context),
                        width: isSel ? 1.5 : 1,
                      ),
                    ),
                    child: Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          gradient: isSel
                              ? const LinearGradient(colors: [Color(0xFF00B4D8), Color(0xFF0077B6)])
                              : null,
                          color: isSel ? null : _surfaceBg(context),
                          shape: BoxShape.circle,
                          border: isSel ? null : Border.all(color: _border(context)),
                        ),
                        child: Center(
                          child: Text(
                            c['symbol']!,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isSel ? Colors.white : _secondaryText(context),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          c['code']!,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
                            color: isSel ? const Color(0xFF00B4D8) : _primaryText(context),
                          ),
                        ),
                        if (c['label'] != null)
                          Text(c['label']!, style: TextStyle(fontSize: 12, color: _secondaryText(context))),
                      ])),
                      if (isSel)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFF00B4D8),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                        ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _cardBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E2A38) : Colors.white;

  Color _surfaceBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF263040) : const Color(0xFFF5F7FA);

  Color _border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2E3F55) : const Color(0xFFE0E6EF);

  Color _primaryText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF1A2533);

  Color _secondaryText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF8DA0B5) : const Color(0xFF5A7080);

  Color _divider(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2E3F55) : const Color(0xFFE0E6EF);
}
