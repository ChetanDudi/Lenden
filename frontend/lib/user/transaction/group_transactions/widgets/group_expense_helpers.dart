import 'package:flutter/material.dart';
import '../../../../widgets/app_colors.dart';
import '../../../../utils/transaction_constants.dart';

final _oidRe = RegExp(r'^[0-9a-f]{24}$');
String emailOf(dynamic field) {
  if (field == null) return '-';
  if (field is Map) {
    final e = (field['email'] ?? '').toString();
    return _oidRe.hasMatch(e) || e.isEmpty ? (field['name']?.toString().isNotEmpty == true ? field['name'].toString() : 'Deleted Account') : e;
  }
  final s = field.toString();
  return _oidRe.hasMatch(s) ? 'Deleted Account' : s;
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

// Canonical list and icon helper now live in transaction_constants.dart.
// Re-exported here so existing callers don't need to change their imports.
const kGroupExpenseCategories = kTxCategories;
const kGroupExpenseCurrencies = kTxCurrencies;

IconData categoryIcon(String? key) => txCatIcon(key);

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
    case 'personal':      return t('personal');
    case 'rent':          return t('rent');
    case 'business':      return t('business');
    case 'travel':        return t('travel');
    default:              return t('other');
  }
}
