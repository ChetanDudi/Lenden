import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';

Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) =>
    showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (ctx, child) {
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: dark
                ? ColorScheme.dark(
                    primary: AppColors.cyan,
                    onPrimary: Colors.white,
                  )
                : ColorScheme.light(
                    primary: AppColors.cyan,
                    onPrimary: Colors.white,
                  ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
            ),
          ),
          child: child!,
        );
      },
    );

Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) =>
    showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (ctx, child) {
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: dark
                ? ColorScheme.dark(
                    primary: AppColors.cyan,
                    onPrimary: Colors.white,
                  )
                : ColorScheme.light(
                    primary: AppColors.cyan,
                    onPrimary: Colors.white,
                  ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
            ),
          ),
          child: child!,
        );
      },
    );
