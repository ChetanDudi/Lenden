import 'package:flutter/material.dart';
import '../../../../widgets/app_colors.dart';

String emailOf(dynamic field) {
  if (field == null) return '-';
  if (field is Map) return (field['email'] ?? '-').toString();
  return field.toString();
}

String fmtDateTime(dynamic dt) {
  if (dt == null) return '';
  try {
    final d = dt is String ? DateTime.parse(dt).toLocal() : dt as DateTime;
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final period = d.hour >= 12 ? 'PM' : 'AM';
    return '${months[d.month - 1]} ${d.day}, ${d.year}  $h:$m $period';
  } catch (_) {
    return '';
  }
}

Widget tricolorBorderBox({
  required Widget child,
  double radius = 18,
  double borderWidth = 2,
  EdgeInsetsGeometry? margin,
  List<BoxShadow>? shadow,
}) {
  return Container(
    margin: margin,
    decoration: BoxDecoration(
      gradient: AppColors.tricolorGradient,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: shadow ??
          [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
    ),
    padding: EdgeInsets.all(borderWidth),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius - borderWidth),
      child: child,
    ),
  );
}

const kGroupExpenseCardColors = [
  Color(0xFFFFF4E6), Color(0xFFE8F5E9), Color(0xFFFCE4EC),
  Color(0xFFE3F2FD), Color(0xFFFFF9C4), Color(0xFFF3E5F5),
];

const kGroupExpenseCategories = [
  {'key': 'food',          'label': 'Food',          'icon': Icons.restaurant_rounded},
  {'key': 'transport',     'label': 'Transport',     'icon': Icons.directions_car_rounded},
  {'key': 'accommodation', 'label': 'Stay',          'icon': Icons.hotel_rounded},
  {'key': 'entertainment', 'label': 'Fun',           'icon': Icons.sports_esports_rounded},
  {'key': 'shopping',      'label': 'Shopping',      'icon': Icons.shopping_cart_rounded},
  {'key': 'utilities',     'label': 'Utilities',     'icon': Icons.electrical_services_rounded},
  {'key': 'medical',       'label': 'Medical',       'icon': Icons.local_hospital_rounded},
  {'key': 'education',     'label': 'Education',     'icon': Icons.school_rounded},
  {'key': 'other',         'label': 'Other',         'icon': Icons.more_horiz_rounded},
];

IconData categoryIcon(String? key) {
  final cat = kGroupExpenseCategories.firstWhere(
    (c) => c['key'] == key,
    orElse: () => kGroupExpenseCategories.last,
  );
  return cat['icon'] as IconData;
}

String categoryLabel(String? key, String Function(String) t) {
  switch (key) {
    case 'food':          return t('category_food_label');
    case 'transport':     return t('category_transport_label');
    case 'accommodation': return t('category_stay_label');
    case 'entertainment': return t('category_fun_label');
    case 'shopping':      return t('category_shopping_label');
    case 'utilities':     return t('category_utilities_label');
    case 'medical':       return t('category_medical_label');
    case 'education':     return t('category_education_label');
    default:              return t('other');
  }
}

const kGroupExpenseCurrencies = [
  {'code': 'INR', 'symbol': '₹', 'label': 'Indian Rupee'},
  {'code': 'USD', 'symbol': '\$', 'label': 'US Dollar'},
  {'code': 'EUR', 'symbol': '€', 'label': 'Euro'},
  {'code': 'GBP', 'symbol': '£', 'label': 'British Pound'},
  {'code': 'JPY', 'symbol': '¥', 'label': 'Japanese Yen'},
  {'code': 'CNY', 'symbol': '¥', 'label': 'Chinese Yuan'},
  {'code': 'CAD', 'symbol': '\$', 'label': 'Canadian Dollar'},
  {'code': 'AUD', 'symbol': '\$', 'label': 'Australian Dollar'},
  {'code': 'CHF', 'symbol': 'Fr', 'label': 'Swiss Franc'},
  {'code': 'RUB', 'symbol': '₽', 'label': 'Russian Ruble'},
];
