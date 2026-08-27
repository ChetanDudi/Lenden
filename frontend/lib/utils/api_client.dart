import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api_config.dart';
import 'auth_navigation.dart';

class ApiMultipartFile {
  final String field;
  final String filename;
  final List<int>? bytes;
  final String? path;
  final MediaType? contentType;

  const ApiMultipartFile({
    required this.field,
    required this.filename,
    this.bytes,
    this.path,
    this.contentType,
  });
}

class ApiClient {
  static final http.Client _client = http.Client();
  static String get _baseUrl => ApiConfig.baseUrl;

  // Called when tokens are cleared due to auth failure so the SessionProvider
  // can wipe its in-memory state without ApiClient needing a direct reference.
  static void Function()? onAuthFailed;

  // Called when the server returns 503 so the app can show a maintenance screen.
  static void Function()? onMaintenance;

  // Secure storage keys
  static const _storage = FlutterSecureStorage();
  static const String _kAccessToken = 'access_token';
  static const String _kRefreshToken = 'refresh_token';

  // Store tokens (call from your auth flow)
  static Future<void> setTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: _kAccessToken, value: accessToken);
    await _storage.write(key: _kRefreshToken, value: refreshToken);
  }

  static Future<void> clearTokens() async {
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: 'user_data');
  }

  static Future<String?> _getAccessToken() async {
    return await _storage.read(key: _kAccessToken);
  }

  static Future<String?> _getRefreshToken() async {
    return await _storage.read(key: _kRefreshToken);
  }

  // Low-level request with auto-refresh on 401
  static Future<http.Response> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? const Duration(seconds: 10);
    final uri = Uri.parse('$_baseUrl$path');
    String? token = await _getAccessToken();

    final headers = <String, String>{
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      if (extraHeaders != null) ...extraHeaders,
    };

    http.Response Function() _onTimeout =
        () => http.Response('{"error":"Connection timed out. The server is taking too long to respond. Please check your internet and try again."}', 408);
    http.Response resp;
    try {
      switch (method.toUpperCase()) {
        case 'GET':
          resp = await _client
              .get(uri, headers: headers)
              .timeout(effectiveTimeout, onTimeout: _onTimeout);
          break;
        case 'POST':
          resp = await _client
              .post(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(effectiveTimeout, onTimeout: _onTimeout);
          break;
        case 'PUT':
          resp = await _client
              .put(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(effectiveTimeout, onTimeout: _onTimeout);
          break;
        case 'PATCH':
          resp = await _client
              .patch(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(effectiveTimeout, onTimeout: _onTimeout);
          break;
        case 'DELETE':
          resp = await _client
              .delete(uri, headers: headers, body: body != null ? jsonEncode(body) : null)
              .timeout(effectiveTimeout, onTimeout: _onTimeout);
          break;
        default:
          throw UnsupportedError('Unsupported HTTP method: $method');
      }
    } catch (e) {
      if (e is SocketException || e is http.ClientException) {
        return http.Response('{"error":"No internet connection. Please check your network and try again."}', 503);
      }
      rethrow;
    }

    if (resp.statusCode == 503) {
      onMaintenance?.call();
      return resp;
    }

    if (resp.statusCode == 440) {
      await clearTokens();
      onAuthFailed?.call();
      AuthNavigation.redirectToLogin();
      return resp;
    }

    // If unauthorized, try refresh and retry once.
    // Only do this when the request actually carried a session token — if
    // there was no token (e.g. a login attempt with a wrong password), a 401
    // is the endpoint rejecting the credentials, not an expired session, so
    // skip the refresh/redirect-to-login flow and let the real error through.
    if (resp.statusCode == 401 && token != null) {
      final refreshed = await _refreshTokens();
      if (refreshed) {
        token = await _getAccessToken();
        final retryHeaders = <String, String>{
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          if (extraHeaders != null) ...extraHeaders,
        };
        switch (method.toUpperCase()) {
          case 'GET':
            resp = await _client
                .get(uri, headers: retryHeaders)
                .timeout(effectiveTimeout, onTimeout: _onTimeout);
            break;
          case 'POST':
            resp = await _client
                .post(uri, headers: retryHeaders, body: jsonEncode(body ?? {}))
                .timeout(effectiveTimeout, onTimeout: _onTimeout);
            break;
          case 'PUT':
            resp = await _client
                .put(uri, headers: retryHeaders, body: jsonEncode(body ?? {}))
                .timeout(effectiveTimeout, onTimeout: _onTimeout);
            break;
          case 'PATCH':
            resp = await _client
                .patch(uri, headers: retryHeaders, body: jsonEncode(body ?? {}))
                .timeout(effectiveTimeout, onTimeout: _onTimeout);
            break;
          case 'DELETE':
            resp = await _client
                .delete(uri, headers: retryHeaders, body: body != null ? jsonEncode(body) : null)
                .timeout(effectiveTimeout, onTimeout: _onTimeout);
            break;
        }
      } else {
        await clearTokens();
        AuthNavigation.redirectToLogin();
      }
    }

    return resp;
  }

  // Refresh tokens using refresh token stored in storage. Returns true if refreshed.
  static Future<bool> _refreshTokens() async {
    final refreshToken = await _getRefreshToken();
    if (refreshToken == null) return false;

    try {
      final uri = Uri.parse(
          '$_baseUrl/api/users/refresh-token'); // adjust if endpoint differs
      final response = await _client.post(uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refreshToken}));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final access =
            data['accessToken'] ?? data['token'] ?? data['access_token'];
        final refresh =
            data['refreshToken'] ?? data['refresh_token'] ?? refreshToken;
        if (access != null) {
          await setTokens(access.toString(), refresh.toString());
          return true;
        }
      } else {
        await clearTokens();
        onAuthFailed?.call();
        AuthNavigation.redirectToLogin();
      }
    } catch (_) {
      // ignore
    }
    return false;
  }

  // Public methods
  static Future<http.Response> get(String path,
      {Map<String, String>? headers, Duration? timeout}) {
    return _request('GET', path, extraHeaders: headers, timeout: timeout);
  }

  static Future<http.Response> post(String path,
      {Map<String, dynamic>? body, Map<String, String>? headers, Duration? timeout}) {
    return _request('POST', path, body: body, extraHeaders: headers, timeout: timeout);
  }

  static Future<http.Response> put(String path,
      {Map<String, dynamic>? body, Map<String, String>? headers, Duration? timeout}) {
    return _request('PUT', path, body: body, extraHeaders: headers, timeout: timeout);
  }

  static Future<http.Response> patch(String path,
      {Map<String, dynamic>? body, Map<String, String>? headers, Duration? timeout}) {
    return _request('PATCH', path, body: body, extraHeaders: headers, timeout: timeout);
  }

  static Future<http.Response> delete(String path,
      {Map<String, dynamic>? body, Map<String, String>? headers, Duration? timeout}) {
    return _request('DELETE', path, body: body, extraHeaders: headers, timeout: timeout);
  }

  static Future<http.Response> postMultipart(
    String path, {
    Map<String, dynamic>? fields,
    List<ApiMultipartFile>? files,
    Map<String, String>? headers,
  }) async {
    return _multipartRequest(
      'POST',
      path,
      fields: fields,
      files: files,
      extraHeaders: headers,
    );
  }

  static Future<http.Response> putMultipart(
    String path, {
    Map<String, dynamic>? fields,
    List<ApiMultipartFile>? files,
    Map<String, String>? headers,
  }) async {
    return _multipartRequest(
      'PUT',
      path,
      fields: fields,
      files: files,
      extraHeaders: headers,
    );
  }

  static Future<http.Response> _multipartRequest(
    String method,
    String path, {
    Map<String, dynamic>? fields,
    List<ApiMultipartFile>? files,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    String? token = await _getAccessToken();

    Future<http.Response> sendRequest(String? accessToken) async {
      final request = http.MultipartRequest(method, uri);
      request.headers.addAll({
        'Accept': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        if (extraHeaders != null) ...extraHeaders,
      });

      (fields ?? {}).forEach((key, value) {
        if (value != null) {
          request.fields[key] = value.toString();
        }
      });

      for (final file in files ?? const <ApiMultipartFile>[]) {
        if (file.bytes != null) {
          request.files.add(
            http.MultipartFile.fromBytes(
              file.field,
              file.bytes!,
              filename: file.filename,
              contentType: file.contentType,
            ),
          );
        } else if (file.path != null && file.path!.isNotEmpty) {
          request.files.add(
            await http.MultipartFile.fromPath(
              file.field,
              file.path!,
              filename: file.filename,
              contentType: file.contentType,
            ),
          );
        }
      }

      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    }

    var response = await sendRequest(token);
    if (response.statusCode == 440) {
      await clearTokens();
      AuthNavigation.redirectToLogin();
      return response;
    }

    if (response.statusCode == 401) {
      final refreshed = await _refreshTokens();
      if (refreshed) {
        token = await _getAccessToken();
        response = await sendRequest(token);
      } else {
        await clearTokens();
        AuthNavigation.redirectToLogin();
      }
    }

    return response;
  }
}
