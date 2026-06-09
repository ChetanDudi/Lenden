import 'dart:convert';
import 'package:flutter/material.dart';
import '../api_config.dart';
import '../otp_input.dart';
import '../utils/api_client.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

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

      if (response.statusCode == 200) {
        return {'success': true};
      } else {
        final responseData = jsonDecode(response.body);
        final raw = (responseData['error'] ?? '').toString().toLowerCase();
        String errorMsg;
        if (response.statusCode == 408 || raw.contains('timeout') || raw.contains('timed out')) {
          errorMsg = 'Server is starting up. Please wait a moment and try again.';
        } else if (response.statusCode == 503 || raw.contains('unavailable')) {
          errorMsg = 'Could not send OTP email. Please check your email address and try again.';
        } else {
          errorMsg = responseData['error'] ?? 'User not found';
        }
        return {'success': false, 'error': errorMsg};
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to send OTP. Please try again.'
      };
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
          'error': responseData['error'] ?? 'OTP verification failed.'
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'OTP verification failed. Please try again.'
      };
    }
  }

  static Future<String?> showOtpInputDialog(BuildContext context) async {
    String? otpValue;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: const Color(0xFFF8F6FA),
          title: Row(
            children: const [
              Icon(Icons.lock_clock, color: Color(0xFF00B4D8), size: 28),
              SizedBox(width: 8),
              Text('Enter OTP', style: TextStyle(color: Colors.black)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter the 6-digit OTP sent to your email:',
                  style: TextStyle(fontSize: 16)),
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
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.deepPurple)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Verify',
                  style: TextStyle(
                      color: Color(0xFF00B4D8), fontWeight: FontWeight.bold)),
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
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
