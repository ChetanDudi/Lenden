import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocaleProvider extends ChangeNotifier {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const _kLocaleGuestKey = 'locale_code_guest';

  String? _userId;
  Locale? _locale;
  Locale? get locale => _locale;

  String _keyFor(String? userId) =>
      userId == null || userId.isEmpty ? _kLocaleGuestKey : 'locale_code_$userId';

  /// Loads the language saved for [userId] (or the shared guest slot when no
  /// one is logged in). Call this whenever the active account changes so
  /// each user/admin keeps their own language instead of sharing one.
  Future<void> loadLocale([String? userId]) async {
    _userId = userId;
    final stored = await _storage.read(key: _keyFor(userId));
    _locale = stored == null || stored.isEmpty ? null : Locale(stored);
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    if (locale == null) {
      await _storage.delete(key: _keyFor(_userId));
    } else {
      await _storage.write(key: _keyFor(_userId), value: locale.languageCode);
    }
    notifyListeners();
  }
}
