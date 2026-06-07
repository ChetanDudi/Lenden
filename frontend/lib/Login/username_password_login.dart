import 'package:flutter/material.dart';
import 'dart:convert';
import '../api_config.dart';
import '../utils/api_client.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

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
      }
      return {'success': false, 'error': responseData['error']};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static void showIncorrectPasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: const Color(0xFFF8F6FA),
        title: Row(
          children: const [
            Icon(Icons.lock_outline, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('Incorrect Password', style: TextStyle(color: Colors.black)),
          ],
        ),
        content: const Text(
          'The password you entered is incorrect.',
          style: TextStyle(fontSize: 16, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child:
                const Text('Close', style: TextStyle(color: Colors.deepPurple)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushNamed(context, '/forgot-password');
            },
            child: const Text('Forgot Password',
                style: TextStyle(
                    color: Color(0xFF00B4D8), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static void showUserNotFoundDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: const Color(0xFFF8F6FA),
        title: Row(
          children: const [
            Icon(Icons.person_off, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text('User Not Found', style: TextStyle(color: Colors.black)),
          ],
        ),
        content: const Text(
          'No user found with these credentials. Would you like to register?',
          style: TextStyle(fontSize: 16, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child:
                const Text('Close', style: TextStyle(color: Colors.deepPurple)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushReplacementNamed(context, '/register');
            },
            child: const Text('Register',
                style: TextStyle(
                    color: Color(0xFF00B4D8), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
