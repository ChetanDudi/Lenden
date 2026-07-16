import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppLockService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const _kPinHashKey = 'app_lock_pin_hash';
  static const _kSaltKey = 'app_lock_salt';
  static const _kEnabledKey = 'app_lock_enabled';

  static String _hash(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  static String _generateSalt() {
    final rand = Random.secure();
    return List.generate(16, (_) => rand.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<bool> isEnabled() async {
    return (await _storage.read(key: _kEnabledKey)) == 'true';
  }

  static Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    await _storage.write(key: _kSaltKey, value: salt);
    await _storage.write(key: _kPinHashKey, value: _hash(pin, salt));
    await _storage.write(key: _kEnabledKey, value: 'true');
  }

  static Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _kSaltKey);
    final storedHash = await _storage.read(key: _kPinHashKey);
    if (salt == null || storedHash == null) return false;
    return _hash(pin, salt) == storedHash;
  }

  static Future<void> disable() async {
    await _storage.delete(key: _kPinHashKey);
    await _storage.delete(key: _kSaltKey);
    await _storage.write(key: _kEnabledKey, value: 'false');
  }
}
