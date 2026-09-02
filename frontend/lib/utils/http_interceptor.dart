import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api_config.dart';
import 'auth_navigation.dart';

class HttpInterceptor {
  static const _storage = FlutterSecureStorage();
  static bool _isRefreshing = false;
  static final List<Future<http.Response> Function()> _pendingRequests = [];

  // In-memory token cache — avoids read-after-write failures on fresh Android
  // installs where FlutterSecureStorage (Keystore) returns null immediately after
  // a write until the Keystore has fully initialised.
  static String? _cachedAccessToken;
  static String? _cachedRefreshToken;

  static String? get cachedAccessToken => _cachedAccessToken;
  static String? get cachedRefreshToken => _cachedRefreshToken;

  static void setAccessToken(String? token) => _cachedAccessToken = token;
  static void setRefreshToken(String? token) => _cachedRefreshToken = token;

  // Helper to build Uri (accepts full URL or relative path)
  static Uri _buildUri(String urlOrPath) {
    if (urlOrPath.startsWith('http://') || urlOrPath.startsWith('https://')) {
      return Uri.parse(urlOrPath);
    }
    final path = urlOrPath.startsWith('/') ? urlOrPath : '/$urlOrPath';
    return Uri.parse('${ApiConfig.baseUrl}$path');
  }

  // Override the global http methods
  static Future<http.Response> get(String url,
      {Map<String, String>? headers}) async {
    return await _makeRequest(() async =>
        http.get(_buildUri(url), headers: await _getHeaders(headers)));
  }

  static Future<http.Response> post(String url,
      {Map<String, String>? headers, Object? body}) async {
    return await _makeRequest(() async => http.post(
          _buildUri(url),
          headers: await _getHeaders(headers),
          body: body != null ? jsonEncode(body) : null,
        ));
  }

  static Future<http.Response> put(String url,
      {Map<String, String>? headers, Object? body}) async {
    return await _makeRequest(() async => http.put(
          _buildUri(url),
          headers: await _getHeaders(headers),
          body: body != null ? jsonEncode(body) : null,
        ));
  }

  static Future<http.Response> delete(String url,
      {Map<String, String>? headers}) async {
    return await _makeRequest(() async =>
        http.delete(_buildUri(url), headers: await _getHeaders(headers)));
  }

  static Future<http.MultipartRequest> multipartRequest(
      String method, String url) async {
    final request = http.MultipartRequest(method, _buildUri(url));
    final headers = await _getHeaders({});
    request.headers.addAll(headers);
    return request;
  }

  static Future<Map<String, String>> _getHeaders(
      Map<String, String>? additionalHeaders) async {
    final accessToken = _cachedAccessToken ?? await _storage.read(key: 'access_token');
    Map<String, String> headers = {
      'Accept': 'application/json',
      'User-Agent': 'Lenden-Flutter-App/1.0',
    };
    if (additionalHeaders != null) headers.addAll(additionalHeaders);
    if (accessToken != null) headers['Authorization'] = 'Bearer $accessToken';
    return headers;
  }

  static Future<http.Response> _makeRequest(
      Future<http.Response> Function() request) async {
    // If we're already refreshing tokens, queue this request
    if (_isRefreshing) return await _queueRequest(request);

    // First attempt
    http.Response response = await request().timeout(
      const Duration(seconds: 30),
      onTimeout: () => http.Response('{"error":"timeout"}', 408),
    );

    if (response.statusCode == 440) {
      await _clearTokens();
      AuthNavigation.redirectToLogin();
      return response;
    }

    // If unauthorized, try to refresh token and retry
    if (response.statusCode == 401) {
      final refreshToken = _cachedRefreshToken ?? await _storage.read(key: 'refresh_token');
      if (refreshToken != null) {
        // Set refreshing flag to prevent multiple refresh attempts
        _isRefreshing = true;
        try {
          final candidates = [
            {
              'path': '/api/users/refresh-token',
              'body': {'refreshToken': refreshToken}
            },
            {
              'path': '/api/auth/refresh',
              'body': {'refreshToken': refreshToken}
            },
          ];
          bool refreshed = false;
          // True when the server responded (even with a 4xx) — distinguishes
          // a genuine token rejection from a pure network failure.
          bool serverRejected = false;
          for (final c in candidates) {
            try {
              final refreshResponse = await http.post(
                _buildUri(c['path'] as String),
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json'
                },
                body: jsonEncode(c['body']),
              );
              if (refreshResponse.statusCode == 200) {
                final data = jsonDecode(refreshResponse.body);
                final newAccess =
                    (data['accessToken'] ?? data['token'] ?? data['access'])
                        ?.toString();
                final newRefresh =
                    (data['refreshToken'] ?? data['refresh'])?.toString();
                if (newAccess != null && newAccess.isNotEmpty) {
                  _cachedAccessToken = newAccess;
                  await _storage.write(key: 'access_token', value: newAccess);
                  if (newRefresh != null && newRefresh.isNotEmpty) {
                    _cachedRefreshToken = newRefresh;
                    await _storage.write(
                        key: 'refresh_token', value: newRefresh);
                  }
                  refreshed = true;
                  break;
                }
              } else {
                // Server reached but rejected the token (401/400/etc.)
                serverRejected = true;
              }
            } catch (_) {
              // Network error — server unreachable; try next candidate.
              continue;
            }
          }
          if (refreshed) {
            // Process all pending requests
            await _processPendingRequests();

            // Retry the original request with new token
            response = await request().timeout(
              const Duration(seconds: 30),
              onTimeout: () => http.Response('{"error":"timeout"}', 408),
            );
          } else if (serverRejected) {
            // Server confirmed the token is invalid — genuine auth failure.
            await _clearTokensAndProcessPending();
            AuthNavigation.redirectToLogin();
            response = await request().timeout(
              const Duration(seconds: 30),
              onTimeout: () => http.Response('{"error":"timeout"}', 408),
            );
          } else {
            // All refresh attempts failed with network errors (device offline,
            // server unreachable). Don't log the user out — a transient
            // connectivity blip should not end the session.
            await _processPendingRequests();
          }
        } catch (e) {
          // Unexpected exception in refresh machinery — don't logout; let the
          // caller surface the error via the original 401 response.
          await _processPendingRequests();
        } finally {
          _isRefreshing = false;
        }
      } else {
        // No refresh token stored — nothing to try, clear and redirect.
        await _clearTokens();
        AuthNavigation.redirectToLogin();
      }
    }

    return response;
  }

  static Future<http.Response> _queueRequest(
      Future<http.Response> Function() request) async {
    final completer = Completer<http.Response>();
    _pendingRequests.add(() async {
      try {
        final response = await request();
        completer.complete(response);
        return response;
      } catch (e) {
        completer.completeError(e);
        rethrow;
      }
    });
    return completer.future;
  }

  static Future<void> _processPendingRequests() async {
    final requests =
        List<Future<http.Response> Function()>.from(_pendingRequests);
    _pendingRequests.clear();
    for (final req in requests) {
      try {
        await req();
      } catch (e) {
        // ignore per-request errors
      }
    }
  }

  static Future<void> _clearTokensAndProcessPending() async {
    await _clearTokens();
    final requests =
        List<Future<http.Response> Function()>.from(_pendingRequests);
    _pendingRequests.clear();
    for (final req in requests) {
      try {
        await req();
      } catch (_) {}
    }
  }

  static Future<void> _clearTokens() async {
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'user_data');
  }
}
