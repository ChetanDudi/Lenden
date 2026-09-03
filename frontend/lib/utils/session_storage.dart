import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cross-platform session storage.
///
/// Android  → FlutterSecureStorage + EncryptedSharedPreferences (hardware-backed).
/// Windows / Linux / macOS / Web → SharedPreferences (plaintext, fine for dev builds).
///
/// All SharedPreferences keys are prefixed with `_ss_` to avoid conflicts.
class SessionStorage {
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // True when the platform has a reliable secure-storage implementation.
  static bool get _useSecure => !kIsWeb && Platform.isAndroid;

  static Future<String?> read({required String key}) async {
    if (_useSecure) return _secure.read(key: key);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('_ss_$key');
  }

  static Future<void> write({required String key, required String value}) async {
    if (_useSecure) {
      await _secure.write(key: key, value: value);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('_ss_$key', value);
  }

  static Future<void> delete({required String key}) async {
    if (_useSecure) {
      await _secure.delete(key: key);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('_ss_$key');
  }

  static Future<void> deleteAll() async {
    if (_useSecure) {
      await _secure.deleteAll();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('_ss_')).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
