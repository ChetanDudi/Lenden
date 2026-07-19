import 'dart:convert';
import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';
import '../otp_input.dart';
import '../utils/api_client.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

class EmailOtpLogin {
  static Future<Map<String, dynamic>> sendOtp({
    required String email,
    required BuildContext context,
  }) async {
    try {
      final response = await ApiClient.post(
        '/api/users/send-login-otp',
        body: {'email': email},
        timeout: const Duration(seconds: 90),
      );

      final t = AppLocalizations.of(context).t;
      if (response.statusCode == 200) {
        return {'success': true};
      } else {
        final responseData = jsonDecode(response.body);
        final raw = (responseData['error'] ?? '').toString().toLowerCase();
        String errorMsg;
        if (response.statusCode == 408 || raw.contains('timeout') || raw.contains('timed out')) {
          errorMsg = t('server_starting_up');
        } else if (response.statusCode == 503 || raw.contains('unavailable')) {
          errorMsg = t('could_not_send_otp_email');
        } else {
          errorMsg = responseData['error'] ?? t('user_not_found');
        }
        return {'success': false, 'error': errorMsg};
      }
    } catch (e) {
      final t = AppLocalizations.of(context).t;
      if (e is SocketException) {
        return {'success': false, 'error': 'No internet connection. Please check your network and try again.'};
      }
      return {'success': false, 'error': t('failed_to_send_otp_retry')};
    }
  }

  static Future<Map<String, dynamic>> verifyOtp({
    required String email,
    required String otp,
    required BuildContext context,
    String? deviceId,
  }) async {
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String deviceName;
      if (kIsWeb) {
        deviceName = 'Web Browser';
      } else {
        if (Platform.isAndroid) {
          AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
          deviceName = androidInfo.model;
        } else if (Platform.isIOS) {
          IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
          deviceName = iosInfo.utsname.machine;
        } else if (Platform.isLinux) {
          LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;
          deviceName = linuxInfo.name;
        } else if (Platform.isWindows) {
          WindowsDeviceInfo windowsInfo = await deviceInfo.windowsInfo;
          deviceName = windowsInfo.computerName;
        } else if (Platform.isMacOS) {
          MacOsDeviceInfo macOsInfo = await deviceInfo.macOsInfo;
          deviceName = macOsInfo.computerName;
        } else {
          deviceName = 'Unknown Device';
        }
      }
      final response = await ApiClient.post('/api/users/login-with-otp', body: {
        'email': email,
        'otp': otp,
        'deviceName': deviceName,
        if (deviceId != null) 'deviceId': deviceId,
      });

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final userOrAdmin = responseData['user'] ?? responseData['admin'];
        final userType = responseData['userType'] ?? 'user';
        final accessToken = responseData['accessToken'];
        final refreshToken = responseData['refreshToken'];

        print(
            '🎫 Access Token: ${accessToken != null ? 'Present' : 'Missing'}');
        print(
            '🎫 Refresh Token: ${refreshToken != null ? 'Present' : 'Missing'}');

        // Check if userOrAdmin is null or empty
        if (userOrAdmin == null) {}

        // Check if tokens are null or empty
        if (accessToken == null || accessToken.isEmpty) {}

        if (refreshToken == null || refreshToken.isEmpty) {}

        return {
          'success': true,
          'userOrAdmin': userOrAdmin,
          'userType': userType,
          'accessToken': accessToken,
          'refreshToken': refreshToken,
          'dailyLoginReward': responseData['dailyLoginReward'],
        };
      } else if (response.statusCode == 403 &&
          responseData['canRecover'] == true) {
        return {
          'success': false,
          'canRecover': true,
          'error': responseData['error'],
          'email': responseData['email'],
          'username': responseData['username'],
        };
      } else {
        return {
          'success': false,
          'error': responseData['error'] ?? AppLocalizations.of(context).t('otp_verification_failed')
        };
      }
    } catch (e) {
      if (e is SocketException) {
        return {'success': false, 'error': 'No internet connection. Please check your network and try again.'};
      }
      return {
        'success': false,
        'error': AppLocalizations.of(context).t('otp_verification_failed_retry')
      };
    }
  }

  static Future<String?> showOtpInputDialog(BuildContext context) async {
    String? otpValue;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final t = AppLocalizations.of(ctx).t;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: AppThemeColors.cardBg(ctx),
          title: Row(
            children: [
              const Icon(Icons.lock_clock, color: AppColors.cyan, size: 28),
              const SizedBox(width: 8),
              Text(t('enter_otp_title'),
                  style: TextStyle(color: AppThemeColors.primaryText(ctx))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('enter_6_digit_otp'),
                  style: TextStyle(
                      fontSize: 16, color: AppThemeColors.primaryText(ctx))),
              const SizedBox(height: 16),
              OtpInput(
                onChanged: (val) => otpValue = val,
                enabled: true,
                autoFocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t('cancel'),
                  style: const TextStyle(color: Colors.deepPurple)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
              },
              child: Text(t('verify'),
                  style: const TextStyle(
                      color: AppColors.cyan, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
    return otpValue;
  }

  static void showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) {
        final t = AppLocalizations.of(ctx).t;
        return AlertDialog(
          backgroundColor: AppThemeColors.cardBg(ctx),
          title: Text(t('error'),
              style: TextStyle(color: AppThemeColors.primaryText(ctx))),
          content: Text(message,
              style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t('ok')),
            ),
          ],
        );
      },
    );
  }
}
