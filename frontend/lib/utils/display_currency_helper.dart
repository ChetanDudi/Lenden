import 'dart:convert';
import 'api_client.dart';
import 'transaction_constants.dart';

/// Static symbol lookup. Falls back to the currency code for unknown currencies.
String currencySymbolFor(String? code) => txCurrencySymbol(code);

class DisplayCurrencyHelper {
  static Future<DisplayCurrencyData> load() async {
    try {
      final response = await ApiClient.get('/api/currency-conversions/matrix');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        final currencies = _parseCurrencies(
          data['currencies'] ??
              data['currencyDefinitions'] ??
              data['supportedCurrencies'],
        );
        final rates = <String, double>{};
        for (final row in (data['matrix'] as List<dynamic>? ?? const [])) {
          final base = (row['baseCurrency'] ?? '').toString().toUpperCase();
          final quote = (row['quoteCurrency'] ?? '').toString().toUpperCase();
          final available = row['available'] != false;
          final rate = double.tryParse((row['rate'] ?? '').toString());
          if (base.isEmpty || quote.isEmpty || !available || rate == null) {
            continue;
          }
          rates['$base->$quote'] = rate;
        }
        return DisplayCurrencyData(currencies: currencies, rates: rates);
      }
    } catch (_) {}

    final fallbackResponse =
        await ApiClient.get('/api/currency-conversions/supported');
    final fallbackData = jsonDecode(fallbackResponse.body) as Map<String, dynamic>;
    if (fallbackResponse.statusCode != 200) {
      throw Exception(
        (fallbackData['error'] ?? 'Failed to load currency display data')
            .toString(),
      );
    }

    return DisplayCurrencyData(
      currencies: _parseCurrencies(
        fallbackData['currencies'] ??
            fallbackData['currencyDefinitions'] ??
            fallbackData['supportedCurrencies'],
      ),
      rates: const {},
    );
  }

  static List<Map<String, String>> _parseCurrencies(dynamic rawCurrencies) {
    return (rawCurrencies as List<dynamic>? ?? const [])
        .map((item) {
          if (item is String) {
            final code = item.toUpperCase();
            return {
              'code': code,
              'symbol': code == 'INR' ? '₹' : code,
              'label': '',
            };
          }
          return {
            'code': (item['code'] ?? 'INR').toString().toUpperCase(),
            'symbol': (item['symbol'] ?? item['code'] ?? '₹').toString(),
            'label': (item['label'] ?? '').toString(),
          };
        })
        .toList();
  }
}

class DisplayCurrencyData {
  final List<Map<String, String>> currencies;
  final Map<String, double> rates;

  const DisplayCurrencyData({
    required this.currencies,
    required this.rates,
  });

  double convert(num amount, String fromCurrency, String toCurrency) {
    final from = fromCurrency.toUpperCase();
    final to = toCurrency.toUpperCase();
    if (from == to) return amount.toDouble();
    final rate = rates['$from->$to'];
    if (rate == null) return amount.toDouble();
    return double.parse((amount * rate).toStringAsFixed(2));
  }

  bool canConvert(String fromCurrency, String toCurrency) {
    final from = fromCurrency.toUpperCase();
    final to = toCurrency.toUpperCase();
    if (from == to) return true;
    return rates.containsKey('$from->$to');
  }

  String symbolFor(String currencyCode) {
    final code = currencyCode.toUpperCase();
    final match = currencies.firstWhere(
      (item) => item['code'] == code,
      orElse: () => const {'code': 'INR', 'symbol': '₹', 'label': ''},
    );
    return match['symbol'] ?? code;
  }
}
