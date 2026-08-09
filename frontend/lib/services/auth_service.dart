import 'dart:convert';
import '../utils/api_client.dart';

/// Centralises all auth, OTP, and password-management API calls.
class AuthService {
  // ── Registration ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> register(
      Map<String, dynamic> body) async {
    final res = await ApiClient.post('/api/users/register', body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyRegistrationOtp(
      {required String email, required String otp}) async {
    final res = await ApiClient.post('/api/users/verify-otp',
        body: {'email': email, 'otp': otp});
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> resendRegistrationOtp(
      String email) async {
    final res =
        await ApiClient.post('/api/users/resend-otp', body: {'email': email});
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> loginWithEmail(
      Map<String, dynamic> body) async {
    final res = await ApiClient.post('/api/users/login', body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> sendLoginOtp(String email) async {
    final res = await ApiClient.post('/api/users/send-login-otp',
        body: {'email': email});
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyLoginOtp(
      Map<String, dynamic> body) async {
    final res = await ApiClient.post('/api/users/verify-login-otp', body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> loginWithGoogle(
      String idToken, Map<String, dynamic> extras) async {
    final res = await ApiClient.post('/api/users/google-login',
        body: {'idToken': idToken, ...extras});
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Forgot / reset password ───────────────────────────────────────────────

  static Future<Map<String, dynamic>> sendResetOtp(String email) async {
    final res = await ApiClient.post('/api/users/send-reset-otp',
        body: {'email': email});
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyResetOtp(
      {required String email, required String otp}) async {
    final res = await ApiClient.post('/api/users/verify-reset-otp',
        body: {'email': email, 'otp': otp});
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> resetPassword(
      Map<String, dynamic> body) async {
    final res = await ApiClient.post('/api/users/reset-password', body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Set password (first time, no existing password) ───────────────────────

  static Future<Map<String, dynamic>> sendSetPasswordOtp() async {
    final res = await ApiClient.post('/api/users/set-password/send-otp');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifySetPasswordIdentity(
      Map<String, dynamic> body) async {
    final res = await ApiClient.post('/api/users/set-password/verify-identity',
        body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> setPassword(
      Map<String, dynamic> body) async {
    final res = await ApiClient.post('/api/users/set-password', body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Change password (knows current password) ──────────────────────────────

  static Future<Map<String, dynamic>> sendChangePasswordOtp() async {
    final res = await ApiClient.post('/api/users/change-password/send-otp');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyChangePasswordIdentity(
      Map<String, dynamic> body) async {
    final res = await ApiClient.post(
        '/api/users/change-password/verify-identity',
        body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> changePassword(
      Map<String, dynamic> body) async {
    final res =
        await ApiClient.post('/api/users/change-password', body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Alternative email OTP ─────────────────────────────────────────────────

  static Future<Map<String, dynamic>> sendAlternativeEmailOtp() async {
    final res =
        await ApiClient.post('/api/users/alternative-email/send-otp');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyAlternativeEmailOtp(
      String otp) async {
    final res = await ApiClient.post('/api/users/alternative-email/verify-otp',
        body: {'otp': otp});
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateAlternativeEmail(
      String email) async {
    final res = await ApiClient.put('/api/users/alternative-email',
        body: {'alternativeEmail': email});
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Session / refresh ─────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> refreshToken(
      String refreshToken) async {
    final res = await ApiClient.post('/api/users/refresh-token',
        body: {'refreshToken': refreshToken});
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> logout() async {
    await ApiClient.post('/api/users/logout');
  }
}
