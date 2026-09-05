import 'package:flutter/material.dart';

/// Master category list used across quick, secure, and group transactions.
/// Every field: key (String), label (String), icon (IconData), color (Color).
const kTxCategories = <Map<String, Object>>[
  {'key': 'food',          'label': 'Food & Dining',       'icon': Icons.restaurant_rounded,          'color': Color(0xFF9C27B0)},
  {'key': 'transport',     'label': 'Transport',            'icon': Icons.directions_car_rounded,      'color': Color(0xFF1A8FBB)},
  {'key': 'accommodation', 'label': 'Accommodation',        'icon': Icons.hotel_rounded,               'color': Color(0xFF2193B0)},
  {'key': 'entertainment', 'label': 'Entertainment',        'icon': Icons.sports_esports_rounded,      'color': Color(0xFF764BA2)},
  {'key': 'shopping',      'label': 'Shopping',             'icon': Icons.shopping_cart_rounded,       'color': Color(0xFFE91E63)},
  {'key': 'utilities',     'label': 'Utilities',            'icon': Icons.electrical_services_rounded, 'color': Color(0xFF2B78E4)},
  {'key': 'medical',       'label': 'Medical / Healthcare', 'icon': Icons.local_hospital_rounded,      'color': Color(0xFF1CA870)},
  {'key': 'education',     'label': 'Education',            'icon': Icons.school_rounded,              'color': Color(0xFF8E54E9)},
  {'key': 'personal',      'label': 'Personal',             'icon': Icons.person_rounded,              'color': Color(0xFFE0417E)},
  {'key': 'rent',          'label': 'Rent',                 'icon': Icons.home_rounded,                'color': Color(0xFFE65C00)},
  {'key': 'business',      'label': 'Business',             'icon': Icons.business_center_rounded,     'color': Color(0xFF3B5FCC)},
  {'key': 'travel',        'label': 'Travel',               'icon': Icons.flight_rounded,              'color': Color(0xFFFF7043)},
  {'key': 'other',         'label': 'Other',                'icon': Icons.more_horiz_rounded,          'color': Color(0xFF607D8B)},
];

/// Per-category 3-stop gradient colours for card backgrounds.
const kTxCategoryGradients = <String, List<Color>>{
  'food':          [Color(0xFFD372F0), Color(0xFF9C27B0), Color(0xFF4A148C)],
  'transport':     [Color(0xFF26D0CE), Color(0xFF1A8FBB), Color(0xFF0A5175)],
  'accommodation': [Color(0xFF6DD5ED), Color(0xFF2193B0), Color(0xFF0A5E80)],
  'entertainment': [Color(0xFF667EEA), Color(0xFF764BA2), Color(0xFF3D2A8A)],
  'shopping':      [Color(0xFFFF6CAB), Color(0xFFE91E63), Color(0xFF880E4F)],
  'utilities':     [Color(0xFF4FACFE), Color(0xFF2B78E4), Color(0xFF0D3F9F)],
  'medical':       [Color(0xFF43E97B), Color(0xFF1CA870), Color(0xFF0B6640)],
  'education':     [Color(0xFF4776E6), Color(0xFF8E54E9), Color(0xFF2E1A8F)],
  'personal':      [Color(0xFFFF9A9E), Color(0xFFE0417E), Color(0xFF8B0060)],
  'rent':          [Color(0xFFFF9900), Color(0xFFE65C00), Color(0xFF8B2500)],
  'business':      [Color(0xFF3B5FCC), Color(0xFF1A2E8A), Color(0xFF0D1240)],
  'travel':        [Color(0xFFFFD200), Color(0xFFFF7043), Color(0xFFBF360C)],
  'other':         [Color(0xFF43E97B), Color(0xFF1FD58E), Color(0xFF0BAB78)],
};

/// Gradient used when a transaction is fully cleared / settled.
const kTxClearedGradient = <Color>[
  Color(0xFF00B09B), Color(0xFF00796B), Color(0xFF004D40),
];

/// Shared currency list for all transaction forms.
/// Fields: code (String), symbol (String), label (String).
const kTxCurrencies = <Map<String, String>>[
  {'code': 'INR', 'symbol': '₹',  'label': 'Indian Rupee'},
  {'code': 'USD', 'symbol': '\$', 'label': 'US Dollar'},
  {'code': 'EUR', 'symbol': '€',  'label': 'Euro'},
  {'code': 'GBP', 'symbol': '£',  'label': 'British Pound'},
  {'code': 'JPY', 'symbol': '¥',  'label': 'Japanese Yen'},
  {'code': 'CNY', 'symbol': '¥',  'label': 'Chinese Yuan'},
  {'code': 'CAD', 'symbol': '\$', 'label': 'Canadian Dollar'},
  {'code': 'AUD', 'symbol': '\$', 'label': 'Australian Dollar'},
  {'code': 'CHF', 'symbol': 'Fr', 'label': 'Swiss Franc'},
  {'code': 'RUB', 'symbol': '₽',  'label': 'Russian Ruble'},
];

/// Icon for [key]; falls back to `more_horiz` for unknown keys.
IconData txCatIcon(String? key) {
  final cat = kTxCategories.firstWhere(
    (c) => c['key'] == key,
    orElse: () => kTxCategories.last,
  );
  return cat['icon'] as IconData;
}

/// English short label for [key].
String txCatLabel(String? key) {
  final cat = kTxCategories.firstWhere(
    (c) => c['key'] == key,
    orElse: () => kTxCategories.last,
  );
  return cat['label'] as String;
}

/// Accent colour for [key].
Color txCatColor(String? key) {
  final cat = kTxCategories.firstWhere(
    (c) => c['key'] == key,
    orElse: () => kTxCategories.last,
  );
  return cat['color'] as Color;
}

/// 3-stop gradient colours for card backgrounds.
List<Color> txCatGradient(String category) =>
    kTxCategoryGradients[category] ?? kTxCategoryGradients['other']!;

/// Currency symbol for [code]; falls back to '₹'.
String txCurrencySymbol(String? code) {
  final upper = (code ?? 'INR').toUpperCase();
  return kTxCurrencies.firstWhere(
    (c) => c['code'] == upper,
    orElse: () => {'code': upper, 'symbol': '₹', 'label': ''},
  )['symbol']!;
}

/// PDF-safe ASCII symbol for [code]. The `pdf` package cannot render
/// multi-byte Unicode glyphs (₹, ₽) so we use ASCII equivalents.
String txPdfSymbol(String code) {
  const _safe = <String, String>{
    'USD': r'$', 'CAD': r'$', 'AUD': r'$', 'HKD': r'$',
    'SGD': r'$', 'NZD': r'$', 'MXN': r'$',
    'EUR': '€', 'GBP': '£', 'JPY': '¥', 'CNY': '¥',
    'CHF': 'Fr', 'INR': 'Rs.', 'RUB': 'RUB',
    'KRW': 'KRW', 'BRL': r'R$', 'ZAR': 'R',
  };
  return _safe[code.toUpperCase()] ?? code.toUpperCase();
}
