import 'package:flutter/material.dart';
import 'dart:async';
import 'utils/session_storage.dart';
import 'dart:convert';
import 'utils/http_interceptor.dart';
import 'utils/share_utils.dart' show clearReferralCache;
import 'user/chats/chat_encryption_service.dart';

class SessionProvider extends ChangeNotifier {
  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>>? _counterparties;
  DateTime? _counterpartiesLastFetched;
  Map<String, int>? _mutualFriendCounts;
  DateTime? _mutualCountsLastFetched;
  String? _role;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get token => _accessToken; // For backward compatibility
  Map<String, dynamic>? get user => _user;
  List<Map<String, dynamic>>? get counterparties => _counterparties;
  DateTime? get counterpartiesLastFetched => _counterpartiesLastFetched;
  Map<String, int>? get mutualFriendCounts => _mutualFriendCounts;
  DateTime? get mutualCountsLastFetched => _mutualCountsLastFetched;
  String? get role => _role;
  bool get isAdmin => _role == 'admin';

  bool _isSubscribed = false;
  String? _subscriptionPlan;
  DateTime? _subscriptionEndDate;
  List<Map<String, dynamic>>? _subscriptionHistory;
  int? _free;
  bool _autoRenew = false;
  bool _subscriptionAdminDeactivated = false;
  String? _subscriptionDeactivationReason;
  int? _subscriptionRemainingDays;
  // null = all features unlocked (legacy / no plan restrictions); List = explicit allow-list
  List<String>? _allowedFeatures;

  int? _freeQuickTransactionsRemaining;
  int? _freeUserTransactionsRemaining;
  int? _freeGroupsRemaining;
  int? _lenDenCoins;
  Map<String, dynamic> _coinPricing = const {
    'privateChatMessageCost': 5,
    'groupChatMessageCost': 7,
    'quickTransactionCost': 5,
    'secureTransactionCost': 10,
    'groupCreationCost': 20,
    'groupExpenseCost': 5,
    'dailyLoginReward': 1,
    'leaderboardRank1Reward': 20,
    'leaderboardRank2Reward': 10,
    'leaderboardRank3Reward': 5,
    'coinValueCurrency': 'INR',
    'coinValue': 0.10,
  };

  bool get isSubscribed => _isSubscribed;
  String? get subscriptionPlan => _subscriptionPlan;
  DateTime? get subscriptionEndDate => _subscriptionEndDate;
  List<Map<String, dynamic>>? get subscriptionHistory => _subscriptionHistory;
  bool get subscriptionAdminDeactivated => _subscriptionAdminDeactivated;
  String? get subscriptionDeactivationReason => _subscriptionDeactivationReason;
  int? get subscriptionRemainingDays => _subscriptionRemainingDays;
  int? get free => _free;
  bool get autoRenew => _autoRenew;
  List<String>? get allowedFeatures => _allowedFeatures;

  /// Returns true when the user is subscribed AND their plan includes [featureKey].
  /// A null allowedFeatures list (legacy plan) grants access to every feature.
  bool hasFeature(String featureKey) {
    if (!_isSubscribed) return false;
    if (_allowedFeatures == null) return true;
    return _allowedFeatures!.contains(featureKey);
  }
  int? get freeQuickTransactionsRemaining => _freeQuickTransactionsRemaining;
  int? get freeUserTransactionsRemaining => _freeUserTransactionsRemaining;
  int? get freeGroupsRemaining => _freeGroupsRemaining;
  int? get lenDenCoins => _lenDenCoins;

  int get privateChatCoinCost    => (_coinPricing['privateChatMessageCost'] as num? ?? 5).toInt();
  int get groupChatCoinCost      => (_coinPricing['groupChatMessageCost'] as num? ?? 7).toInt();
  int get quickTransactionCoinCost => (_coinPricing['quickTransactionCost'] as num? ?? 5).toInt();
  int get secureTransactionCoinCost => (_coinPricing['secureTransactionCost'] as num? ?? 10).toInt();
  int get groupCreationCoinCost  => (_coinPricing['groupCreationCost'] as num? ?? 20).toInt();
  int get groupExpenseCoinCost   => (_coinPricing['groupExpenseCost'] as num? ?? 5).toInt();
  int get dailyLoginCoinReward   => (_coinPricing['dailyLoginReward'] as num? ?? 1).toInt();
  Map<String, dynamic> get coinPricingConfig => Map.unmodifiable(_coinPricing);

  static const String _deviceIdKey = 'device_id';

  Future<void> loadTokens() async {
    try {
      final results = await Future.wait([
        SessionStorage.read(key: 'access_token'),
        SessionStorage.read(key: 'refresh_token'),
      ]);
      _accessToken = results[0];
      _refreshToken = results[1];
    } catch (_) {
      try { await SessionStorage.deleteAll(); } catch (_) {}
      _accessToken = null;
      _refreshToken = null;
    }
    notifyListeners();
  }

  Future<void> saveTokens(String accessToken, String refreshToken) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    HttpInterceptor.setAccessToken(accessToken);
    HttpInterceptor.setRefreshToken(refreshToken);
    await SessionStorage.write(key: 'access_token', value: accessToken);
    await SessionStorage.write(key: 'refresh_token', value: refreshToken);
    notifyListeners();
  }

  Future<void> saveToken(String token) async {
    if (_refreshToken != null) {
      await saveTokens(token, _refreshToken!);
    } else {
      _accessToken = token;
      HttpInterceptor.setAccessToken(token);
      await SessionStorage.write(key: 'access_token', value: token);
      notifyListeners();
    }
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _user = null;
    _role = null;
    HttpInterceptor.setAccessToken(null);
    HttpInterceptor.setRefreshToken(null);
    try {
      await Future.wait([
        SessionStorage.delete(key: 'access_token'),
        SessionStorage.delete(key: 'refresh_token'),
        SessionStorage.delete(key: 'user_data'),
      ]);
    } catch (_) {
      try { await SessionStorage.deleteAll(); } catch (_) {}
    }
    clearCounterparties();
    clearSubscription();
    notifyListeners();
  }

  Future<void> clearToken() async {
    // For backward compatibility
    await clearTokens();
  }

  Future<void> initSession() async {
    // Read all three storage keys in parallel — single round trip.
    // Wrapped in try-catch: on Windows, a corrupt .dat file causes all concurrent
    // reads to race on deletion (errno=32). We wipe and treat as logged out.
    List<String?> results;
    try {
      results = await Future.wait([
        SessionStorage.read(key: 'access_token'),
        SessionStorage.read(key: 'refresh_token'),
        SessionStorage.read(key: 'user_data'),
      ]);
    } catch (_) {
      // Storage read failed (e.g. transient Android Keystore hiccup).
      // Leave stored tokens intact — do NOT delete them. Surfacing as
      // "not logged in" is safe; a restart will usually recover the read.
      _user = null;
      _role = null;
      notifyListeners();
      return;
    }
    _accessToken = results[0];
    _refreshToken = results[1];
    HttpInterceptor.setAccessToken(_accessToken);
    HttpInterceptor.setRefreshToken(_refreshToken);

    if (_accessToken == null) {
      _user = null;
      _role = null;
      notifyListeners();
      return;
    }

    // Restore cached user — avoids a network round-trip on every app open.
    if (results[2] != null) {
      try {
        final user = jsonDecode(results[2]!);
        _user = user;
        _role = (user['role'] as String?) ?? 'user';
      } catch (_) {}
    }

    if (_user != null) {
      // Returning user with cached session: show the app immediately,
      // then do all secondary network work in the background.
      notifyListeners();
      unawaited(_doBackgroundInit(refreshProfile: true));
      return;
    }

    // First launch / cleared cache: we must fetch the profile before
    // showing the app so the UI knows who is logged in.
    try {
      var response = await HttpInterceptor.get('/api/users/me')
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        response = await HttpInterceptor.get('/api/admins/me')
            .timeout(const Duration(seconds: 30));
      }
      if (response.statusCode == 200) {
        var user = jsonDecode(response.body);
        if (user['profileImage'] is Map &&
            user['profileImage']['url'] != null) {
          user['profileImage'] = user['profileImage']['url'];
        }
        final resolvedRole =
            response.request?.url.path.contains('/admins/') ?? false
                ? 'admin'
                : 'user';
        user['role'] = resolvedRole;
        _user = user;
        _role = resolvedRole;
        await _saveUserData(user);
        notifyListeners();
        unawaited(_doBackgroundInit(refreshProfile: false));
      } else {
        // The interceptor already handles genuine token rejection:
        // it clears tokens + calls redirectToLogin() when the server
        // confirms the refresh token is invalid. A non-200 here means
        // a transient network issue prevented the refresh — do NOT
        // clear tokens or the 7-day refresh token is permanently lost.
        notifyListeners();
      }
    } catch (_) {
      // Network error: keep tokens intact.
      notifyListeners();
    }
  }

  /// Runs after the UI is already visible: refreshes profile (optional),
  /// initialises chat encryption, and loads subscription/freebie data —
  /// all in parallel so none of them block each other.
  Future<void> _doBackgroundInit({required bool refreshProfile}) async {
    try {
      await Future.wait([
        if (refreshProfile) _refreshProfileSilently(),
        _ensureChatEncryptionReady(),
        _loadSecondaryData(),
      ]);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _refreshProfileSilently() async {
    try {
      final resolvedRole = _role == 'admin' ? 'admin' : 'user';
      final profileUrl =
          resolvedRole == 'admin' ? '/api/admins/me' : '/api/users/me';
      final response = await HttpInterceptor.get(profileUrl)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final freshUser = jsonDecode(response.body);
        if (freshUser['profileImage'] is Map &&
            freshUser['profileImage']['url'] != null) {
          freshUser['profileImage'] = freshUser['profileImage']['url'];
        }
        freshUser['role'] = resolvedRole;
        _user = freshUser;
        _role = resolvedRole;
        await _saveUserData(freshUser);
      }
      // Non-200: the interceptor already handled genuine auth failures
      // (it redirects to login when the server confirms the refresh token
      // is invalid). A 401 here after the interceptor ran means a transient
      // network issue; do NOT clear tokens or the refresh token is lost.
    } catch (_) {}
  }

  /// Fetches subscription status, subscription history, and freebie counts
  /// all in parallel — previously these ran sequentially.
  Future<void> _loadSecondaryData() async {
    await Future.wait([
      checkSubscriptionStatus(),
      fetchSubscriptionHistory(),
      loadFreebieCounts(),
    ]);
  }

  void setUser(Map<String, dynamic> user) {
    // Normalize profileImage to always be a String
    if (user['profileImage'] is Map && user['profileImage']['url'] != null) {
      user['profileImage'] = user['profileImage']['url'];
    }
    _user = user;
    _role = user['role'] ?? 'user';
    _saveUserData(user);
    unawaited(_ensureChatEncryptionReady());
    notifyListeners();
  }

  Future<void> checkSubscriptionStatus() async {
    if (_accessToken == null) return;

    try {
      final response = await HttpInterceptor.get('/api/subscription/status');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _isSubscribed = data['subscribed'] ?? false;
        if (_isSubscribed) {
          _subscriptionPlan = data['subscriptionPlan'];
          _subscriptionEndDate = DateTime.parse(data['endDate']);
          _free = data['free'];
          _autoRenew = data['autoRenew'] ?? false;
          _subscriptionAdminDeactivated = false;
          _subscriptionDeactivationReason = null;
          _subscriptionRemainingDays = null;
          final af = data['allowedFeatures'];
          _allowedFeatures = af == null ? null : List<String>.from(af as List);
        } else {
          _subscriptionPlan = data['subscriptionPlan'];
          _subscriptionEndDate = null;
          _free = null;
          _autoRenew = false;
          _allowedFeatures = null;
          _subscriptionAdminDeactivated = data['adminDeactivated'] == true;
          _subscriptionDeactivationReason = data['deactivationReason']?.toString();
          _subscriptionRemainingDays = data['remainingDays'] is int
              ? data['remainingDays'] as int
              : int.tryParse(data['remainingDays']?.toString() ?? '');
        }
        notifyListeners();
      }
    } catch (e) {
      // ignore — subscription status is non-critical
    }
  }

  Future<bool> setAutoRenew(bool enabled) async {
    if (_accessToken == null) return false;
    try {
      final response = await HttpInterceptor.put('/api/subscription/auto-renew',
          body: {'enabled': enabled});
      if (response.statusCode == 200) {
        _autoRenew = enabled;
        notifyListeners();
        return true;
      }
    } catch (e) {
      // ignore — caller surfaces a generic error to the user
    }
    return false;
  }

  Future<void> fetchSubscriptionHistory() async {
    if (_accessToken == null) return;

    try {
      final response = await HttpInterceptor.get('/api/subscription/history');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _subscriptionHistory = List<Map<String, dynamic>>.from(data);
        notifyListeners();
      }
    } catch (e) {
      // ignore — subscription history is non-critical
    }
  }

  Future<void> loadFreebieCounts() async {
    if (_accessToken == null) {
      return;
    }
    try {
      final response = await HttpInterceptor.get('/api/users/freebie-counts');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _freeQuickTransactionsRemaining =
            data['freeQuickTransactionsRemaining'];
        _freeUserTransactionsRemaining = data['freeUserTransactionsRemaining'];
        _freeGroupsRemaining = data['freeGroupsRemaining'];
        _lenDenCoins = (data['lenDenCoins'] as num?)?.toInt();
        if (_user != null && _lenDenCoins != null) {
          _user!['lenDenCoins'] = _lenDenCoins;
        }
        if (data['coinPricing'] is Map) {
          _coinPricing = Map<String, dynamic>.from(data['coinPricing'] as Map);
        }
        notifyListeners();
      }
    } catch (e) {
      print('Error fetching freebie counts: $e');
    }
  }

  Future<Map<String, dynamic>?> checkDailyLoginRewardOnAppOpen() async {
    if (_accessToken == null || _role == 'admin') {
      return null;
    }

    try {
      final response = await HttpInterceptor.post('/api/users/daily-login-reward');
      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final reward =
          Map<String, dynamic>.from(data['dailyLoginReward'] ?? const {});

      _lenDenCoins = (data['lenDenCoins'] as num?)?.toInt();

      if (_user != null) {
        _user!['lenDenCoins'] = _lenDenCoins;
        _user!['lastDailyLoginRewardDate'] = data['lastDailyLoginRewardDate'];
        _user!['lastDailyLoginRewardAt'] = data['lastDailyLoginRewardAt'];
        await _saveUserData(_user!);
      }

      notifyListeners();
      return reward;
    } catch (e) {
      print('Error checking daily login reward on app open: $e');
      return null;
    }
  }

  void updateUserCoins(int totalCoins) {
    _lenDenCoins = totalCoins;
    notifyListeners();
  }

  void setCounterparties(List<Map<String, dynamic>> counterparties) {
    _counterparties = counterparties;
    _counterpartiesLastFetched = DateTime.now();
    notifyListeners();
  }

  void clearCounterparties() {
    _counterparties = null;
    _counterpartiesLastFetched = null;
    notifyListeners();
  }

  void setMutualFriendCounts(Map<String, int> counts) {
    _mutualFriendCounts = counts;
    _mutualCountsLastFetched = DateTime.now();
    notifyListeners();
  }

  void clearMutualFriendCounts() {
    _mutualFriendCounts = null;
    _mutualCountsLastFetched = null;
    notifyListeners();
  }

  Future<void> _saveUserData(Map<String, dynamic> user) async {
    try {
      await SessionStorage.write(key: 'user_data', value: jsonEncode(user));
    } catch (e) {
      print('Failed to persist user data: $e');
    }
  }

  Future<void> refreshUserProfile() async {
    if (_accessToken == null) return;

    try {
      final isAdmin = _role == 'admin';
      final url = isAdmin ? '/api/admins/me' : '/api/users/me';

      final response = await HttpInterceptor.get(url);

      if (response.statusCode == 200) {
        final user = jsonDecode(response.body);
        setUser(user);
      } else if (response.statusCode == 401 || response.statusCode == 440) {
        await logout();
      }
    } catch (e) {
      print('Error refreshing user profile: $e');
    }
  }

  // Method to force clear image cache and refresh profile
  Future<void> forceRefreshProfile() async {
    if (_accessToken == null) return;

    try {
      final isAdmin = _role == 'admin';
      final url = isAdmin ? '/api/admins/me' : '/api/users/me';

      // Add cache busting parameter
      final cacheBustingUrl = '$url?t=${DateTime.now().millisecondsSinceEpoch}';

      final response = await HttpInterceptor.get(cacheBustingUrl, headers: {
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      });

      if (response.statusCode == 200) {
        final user = jsonDecode(response.body);
        setUser(user);
      } else if (response.statusCode == 401 || response.statusCode == 440) {
        await logout();
      }
    } catch (e) {
      print('Error force refreshing user profile: $e');
    }
  }

  Future<void> clearUser() async {
    _user = null;
    _role = null;
    await SessionStorage.delete(key: 'user_data');
    notifyListeners();
  }

  Future<void> _ensureChatEncryptionReady() async {
    if (_role == 'admin') return;
    final userId = _user?['_id']?.toString();
    if (userId == null || userId.isEmpty) return;

    try {
      await ChatEncryptionService.ensureIdentity(userId);
    } catch (e) {
      print('Error initializing chat encryption: $e');
    }
  }

  void clearSubscription() {
    _isSubscribed = false;
    _subscriptionPlan = null;
    _subscriptionEndDate = null;
    _subscriptionHistory = null;
    _free = null;
    _autoRenew = false;
    _allowedFeatures = null;
    _subscriptionAdminDeactivated = false;
    _subscriptionDeactivationReason = null;
    _subscriptionRemainingDays = null;
    _freeQuickTransactionsRemaining = null;
    _freeUserTransactionsRemaining = null;
    _freeGroupsRemaining = null;
    _lenDenCoins = null;
    notifyListeners();
  }

  Future<void> logout() async {
    if (_refreshToken != null) {
      try {
        await HttpInterceptor.post('/api/users/logout',
            body: {'refreshToken': _refreshToken});
      } catch (e) {
        print('Error logging out on server: $e');
      }
    }
    await clearTokens();
    clearUser();
    clearCounterparties();
    clearSubscription();
    clearReferralCache();
  }

  void updateNotificationSettings(Map<String, dynamic> settings) {
    if (_user != null) {
      _user!['notificationSettings'] = settings;
      _saveUserData(_user!);
      notifyListeners();
    }
  }

  Future<void> saveDeviceId(String deviceId) async {
    await SessionStorage.write(key: _deviceIdKey, value: deviceId);
  }

  Future<String?> getDeviceId() async {
    return await SessionStorage.read(key: _deviceIdKey);
  }
}
