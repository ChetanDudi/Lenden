import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';
import 'dart:convert';
import '../utils/api_client.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

class UsernamePasswordLogin {
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
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

      final response = await ApiClient.post('/api/users/login', body: {
        'username': username,
        'password': password,
        'deviceName': deviceName,
        if (deviceId != null) 'deviceId': deviceId,
      });

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Check if it's a user login
        if (responseData['user'] != null) {
          return {
            'success': true,
            'data': responseData['user'],
            'accessToken': responseData['accessToken'],
            'refreshToken': responseData['refreshToken'],
            'userType': 'user',
            'dailyLoginReward': responseData['dailyLoginReward'],
          };
        }
        // Check if it's an admin login
        else if (responseData['admin'] != null) {
          return {
            'success': true,
            'data': responseData['admin'],
            'accessToken': responseData['accessToken'],
            'refreshToken': responseData['refreshToken'],
            'userType': 'admin',
            'dailyLoginReward': responseData['dailyLoginReward'],
          };
        }
      } else if (response.statusCode == 403 &&
          responseData['canRecover'] == true) {
        return {
          'success': false,
          'canRecover': true,
          'error': responseData['error'],
          'email': responseData['email'],
          'username': responseData['username'],
        };
      } else if (response.statusCode == 202 && responseData['requires2FA'] == true) {
        return {
          'success': false,
          'requires2FA': true,
          'email': responseData['email'],
        };
      }
      return {'success': false, 'error': responseData['error']};
    } catch (e) {
      if (e is SocketException) {
        return {'success': false, 'error': 'network_error'};
      }
      return {'success': false, 'error': e.toString()};
    }
  }

  static void showIncorrectPasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final t = AppLocalizations.of(ctx).t;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: AppThemeColors.cardBg(ctx),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF9800), Color(0xFFFFC107)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.lock_outline_rounded,
                      color: Colors.white, size: 36),
                ),
                const SizedBox(height: 18),
                Text(
                  t('incorrect_password_title'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppThemeColors.primaryText(ctx),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  t('incorrect_password_message'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppThemeColors.secondaryText(ctx),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppThemeColors.border(ctx)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: Text(t('close'),
                            style: TextStyle(
                                color: AppThemeColors.secondaryText(ctx),
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          Navigator.pushNamed(ctx, '/forgot-password');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: Text(t('forgot_password'),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static void showUserNotFoundDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final t = AppLocalizations.of(ctx).t;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: AppThemeColors.cardBg(ctx),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0077B6), AppColors.cyan],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cyan.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person_search_rounded, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 18),
                Text(
                  t('account_not_found_title'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppThemeColors.primaryText(ctx),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  t('account_not_found_message'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppThemeColors.secondaryText(ctx),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppThemeColors.border(ctx)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: Text(t('close'),
                            style: TextStyle(
                                color: AppThemeColors.secondaryText(ctx),
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          Navigator.pushReplacementNamed(ctx, '/register');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: Text(t('register'),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
