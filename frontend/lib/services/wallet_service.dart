import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/api_client.dart';

/// Thrown when the server returns a non-200 response.
/// [message] is the `error` field from the JSON body, or a fallback string.
class ServiceException implements Exception {
  final String message;
  const ServiceException(this.message);
  @override
  String toString() => message;
}

Map<String, dynamic> _decode(http.Response res) {
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode != 200 && res.statusCode != 201) {
    throw ServiceException(
        (data['error'] as String?) ?? 'Request failed (${res.statusCode})');
  }
  return data;
}

/// Centralises all /api/wallet/* HTTP calls.
/// Throws [ServiceException] on server errors — widgets catch and show the message.
class WalletService {
  // ── Balance & history ────────────────────────────────────────────────────

  static Future<double> getBalance() async {
    final data = _decode(await ApiClient.get('/api/wallet/balance'));
    return (data['balance'] as num?)?.toDouble() ?? 0;
  }

  /// [type] one of: 'all', 'credit', 'debit'
  static Future<Map<String, dynamic>> getHistory({
    String type = 'all',
    int page = 1,
    int limit = 20,
    String search = '',
  }) async {
    final q = StringBuffer('/api/wallet/history?type=$type&page=$page&limit=$limit');
    if (search.isNotEmpty) q.write('&search=${Uri.encodeComponent(search)}');
    return _decode(await ApiClient.get(q.toString()));
  }

  // ── PIN management ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getPinStatus() async =>
      _decode(await ApiClient.get('/api/wallet/pin/status'));

  static Future<Map<String, dynamic>> sendPinOtp() async =>
      _decode(await ApiClient.post('/api/wallet/pin/send-otp', body: {}));

  static Future<Map<String, dynamic>> verifyPinOtp(String otp) async =>
      _decode(await ApiClient.post('/api/wallet/pin/verify-otp',
          body: {'otp': otp}));

  /// [body] contains {newPin} plus one of {otp} (first-time / forgot) or
  /// {currentPin} (change).
  static Future<Map<String, dynamic>> setPin(Map<String, dynamic> body) async =>
      _decode(await ApiClient.post('/api/wallet/pin/set', body: body));

  static Future<Map<String, dynamic>> removePin(String currentPin) async =>
      _decode(await ApiClient.post('/api/wallet/pin/remove',
          body: {'currentPin': currentPin}));

  // ── Pay user ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> sendPayOtp(
          Map<String, dynamic> body) async =>
      _decode(await ApiClient.post('/api/wallet/pay/send-otp', body: body));

  static Future<Map<String, dynamic>> payWithOtp(
          Map<String, dynamic> body) async =>
      _decode(await ApiClient.post('/api/wallet/pay/verify-otp', body: body));

  // ── Top-up ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> verifyManualTopup(
          Map<String, dynamic> body) async =>
      _decode(await ApiClient.post('/api/wallet/topup/manual/verify',
          body: body));

  // ── Withdrawals ───────────────────────────────────────────────────────────

  static Future<List<dynamic>> getWithdrawals() async {
    final data = _decode(await ApiClient.get('/api/wallet/withdrawals'));
    return data['withdrawals'] as List<dynamic>? ?? [];
  }

  static Future<Map<String, dynamic>> requestWithdrawal(
          Map<String, dynamic> body) async =>
      _decode(await ApiClient.post('/api/wallet/withdraw', body: body));

  // ── Friends list (needed for pay-user lookup) ─────────────────────────────

  static Future<List<dynamic>> getFriends() async {
    final data = _decode(await ApiClient.get('/api/friends'));
    return data['friends'] as List<dynamic>? ?? [];
  }
}
