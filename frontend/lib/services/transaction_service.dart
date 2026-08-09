import 'dart:convert';
import '../utils/api_client.dart';

/// Centralises all /api/transactions/* and /api/group-transactions/* calls.
class TransactionService {
  // ── Quick transactions ────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getQuickTransactions({
    int page = 1,
    int limit = 20,
    String? status,
    String? search,
  }) async {
    final q = StringBuffer('/api/transactions/quick?page=$page&limit=$limit');
    if (status != null) q.write('&status=$status');
    if (search != null && search.isNotEmpty) {
      q.write('&search=${Uri.encodeComponent(search)}');
    }
    final res = await ApiClient.get(q.toString());
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createQuickTransaction(
      Map<String, dynamic> body) async {
    final res =
        await ApiClient.post('/api/transactions/quick', body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateQuickTransaction(
      String id, Map<String, dynamic> body) async {
    final res =
        await ApiClient.put('/api/transactions/quick/$id', body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> deleteQuickTransaction(
      String id) async {
    final res = await ApiClient.delete('/api/transactions/quick/$id');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Secure transactions ───────────────────────────────────────────────────

  static Future<Map<String, dynamic>> sendCounterpartyOtp(
      Map<String, dynamic> body) async {
    final res = await ApiClient.post(
        '/api/transactions/send-counterparty-otp',
        body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyCounterpartyOtp(
      Map<String, dynamic> body) async {
    final res = await ApiClient.post(
        '/api/transactions/verify-counterparty-otp',
        body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> sendUserOtp(
      Map<String, dynamic> body) async {
    final res = await ApiClient.post('/api/transactions/send-user-otp',
        body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyUserOtp(
      Map<String, dynamic> body) async {
    final res = await ApiClient.post('/api/transactions/verify-user-otp',
        body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getSecureTransactions({
    int page = 1,
    int limit = 20,
    String? status,
  }) async {
    final q =
        StringBuffer('/api/transactions/secure?page=$page&limit=$limit');
    if (status != null) q.write('&status=$status');
    final res = await ApiClient.get(q.toString());
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createSecureTransaction(
      Map<String, dynamic> body) async {
    final res =
        await ApiClient.post('/api/transactions/secure', body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Partial payments ──────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> sendPartialPaymentOtp(
      Map<String, dynamic> body) async {
    final res = await ApiClient.post(
        '/api/transactions/send-partial-payment-otp',
        body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyPartialPaymentOtp(
      Map<String, dynamic> body) async {
    final res = await ApiClient.post(
        '/api/transactions/verify-partial-payment-otp',
        body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Group transactions ────────────────────────────────────────────────────

  static Future<List<dynamic>> getGroups() async {
    final res = await ApiClient.get('/api/group-transactions');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['groups'] as List<dynamic>? ?? [];
  }

  static Future<Map<String, dynamic>> createGroup(
      Map<String, dynamic> body) async {
    final res = await ApiClient.post('/api/group-transactions', body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getGroupDetail(String groupId) async {
    final res = await ApiClient.get('/api/group-transactions/$groupId');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> settleGroupBalance(
      String groupId, Map<String, dynamic> body) async {
    final res = await ApiClient.post(
        '/api/group-transactions/$groupId/settle-balance',
        body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyGroupSettleOtp(
      String groupId, Map<String, dynamic> body) async {
    final res = await ApiClient.post(
        '/api/group-transactions/$groupId/otp-verify-settle',
        body: body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getCounterparties() async {
    final res = await ApiClient.get('/api/transactions/counterparties');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getSummary() async {
    final res = await ApiClient.get('/api/transactions/summary');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
