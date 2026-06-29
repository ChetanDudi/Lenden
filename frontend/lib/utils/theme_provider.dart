import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeProvider extends ChangeNotifier {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const _kThemeModeGuestKey = 'theme_mode_guest';

  String? _userId;
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  String _keyFor(String? userId) =>
      userId == null || userId.isEmpty ? _kThemeModeGuestKey : 'theme_mode_$userId';

  /// Loads the theme mode saved for [userId] (or the shared guest slot when
  /// no one is logged in). Call this whenever the active account changes so
  /// each user/admin keeps their own preference instead of sharing one.
  Future<void> loadThemeMode([String? userId]) async {
    _userId = userId;
    final stored = await _storage.read(key: _keyFor(userId));
    _themeMode = _parse(stored);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _storage.write(key: _keyFor(_userId), value: _toKey(mode));
    notifyListeners();
  }

  ThemeMode _parse(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  String _toKey(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
