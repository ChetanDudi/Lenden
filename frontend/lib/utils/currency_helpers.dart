import 'package:flutter/material.dart';

const Map<String, double> _ratesFromINR = {
  'INR': 1.0,
  'USD': 0.012,
  'EUR': 0.011,
  'GBP': 0.0095,
  'JPY': 1.77,
  'AED': 0.044,
  'SGD': 0.016,
  'CAD': 0.016,
  'AUD': 0.018,
  'SAR': 0.045,
};

const Map<String, String> _symbols = {
  'INR': '₹', 'USD': '\$', 'EUR': '€', 'GBP': '£',
  'JPY': '¥', 'AED': 'AED', 'SGD': 'S\$', 'CAD': 'C\$',
  'AUD': 'A\$', 'SAR': 'SAR',
};

const List<String> kSupportedCurrencies = [
  'INR', 'USD', 'EUR', 'GBP', 'JPY', 'AED', 'SGD', 'CAD', 'AUD', 'SAR',
];

const List<String> kBudgetCategories = [
  'Food', 'Groceries', 'Shopping', 'Entertainment', 'Fuel', 'Travel',
  'Medical', 'Education', 'Rent', 'Bills', 'Other',
];

String currencySymbol(String code) => _symbols[code] ?? code;

double convertCurrency(double amount, String from, String to) {
  if (from == to) return amount;
  final fromRate = _ratesFromINR[from] ?? 1.0;
  final toRate   = _ratesFromINR[to]   ?? 1.0;
  return (amount / fromRate) * toRate;
}

IconData currencyIcon(String code) {
  switch (code) {
    case 'USD': case 'CAD': case 'AUD': case 'SGD':
      return Icons.attach_money_rounded;
    case 'EUR':
      return Icons.euro_rounded;
    case 'GBP':
      return Icons.currency_pound_rounded;
    case 'JPY':
      return Icons.currency_yen_rounded;
    default:
      return Icons.currency_rupee_rounded;
  }
}
