import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../utils/api_client.dart';

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    // On web, clientId is required (serverClientId is ignored by the web plugin).
    // On mobile, serverClientId is used to verify the ID token on the backend.
    clientId: kIsWeb
        ? '887637529626-r7tt1nevedtnp1l06fa6rp2vbu6k6m89.apps.googleusercontent.com'
        : null,
    serverClientId:
        '887637529626-r7tt1nevedtnp1l06fa6rp2vbu6k6m89.apps.googleusercontent.com',
    scopes: ['email'],
  );

  /// Triggers the Google account picker and returns the Google ID token,
  /// or null if the user cancelled the sign-in flow.
  static Future<String?> signInAndGetIdToken() async {
    // google_sign_in caches the last-picked account and silently reuses it
    // on subsequent calls, skipping the account picker. Sign out first so
    // the chooser is shown every time, letting the user pick a different
    // Google account if they want to.
    await _googleSignIn.signOut();
    final account = await _googleSignIn.signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    return auth.idToken;
  }

  /// Exchanges a Google ID token for LenDen session tokens via the backend.
  /// Returns the same result shape as EmailPasswordLogin.login/UsernamePasswordLogin.login.
  static Future<Map<String, dynamic>> loginWithGoogle({
    String? deviceId,
    String? deviceName,
  }) async {
    try {
      final idToken = await signInAndGetIdToken();
      if (idToken == null) {
        return {'success': false, 'cancelled': true};
      }

      final response = await ApiClient.post('/api/users/google-login', body: {
        'idToken': idToken,
        if (deviceId != null) 'deviceId': deviceId,
        if (deviceName != null) 'deviceName': deviceName,
      });

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          (responseData['user'] != null || responseData['admin'] != null)) {
        return {
          'success': true,
          'userOrAdmin': responseData['user'] ?? responseData['admin'],
          'accessToken': responseData['accessToken'],
          'refreshToken': responseData['refreshToken'],
          'userType': (responseData['userType'] as String?) ?? 'user',
          'dailyLoginReward': responseData['dailyLoginReward'],
          'isNewUser': responseData['isNewUser'] == true,
        };
      }
      if (response.statusCode == 202 && responseData['requires2FA'] == true) {
        return {
          'success': false,
          'requires2FA': true,
          'email': responseData['email'],
        };
      }
      return {
        'success': false,
        'error': responseData['error'] ?? 'Google sign-in failed'
      };
    } catch (e) {
      if (e is PlatformException && e.code == 'network_error') {
        return {'success': false, 'error': 'network_error'};
      }
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
  }
}
