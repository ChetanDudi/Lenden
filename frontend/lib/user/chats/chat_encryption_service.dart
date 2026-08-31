import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../utils/api_client.dart';
import 'chat_codec.dart';

class ChatEncryptionService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static final X25519 _keyAgreement = X25519();
  static final AesGcm _aesGcm = AesGcm.with256bits();
  static final Hkdf _hkdf =
      Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static const String _keyNamespace = 'chat_identity';
  static const String _hkdfNonce = 'LenDen-E2EE';
  static const String _deviceIdStorageKey = 'chat_identity:device_id';

  // In-memory cache for the current session — ensures _loadKeyPair works
  // even when the underlying secure storage returns null after a write
  // (can happen after reinstall until the Keystore settles).
  static final Map<String, SimpleKeyPairData> _sessionKeyCache = {};

  static String _privateKeyStorageKey(String userId) =>
      '$_keyNamespace:${userId}:private';

  static String _publicKeyStorageKey(String userId) =>
      '$_keyNamespace:${userId}:public';

  /// Stable per-installation device identifier, independent of which user
  /// account is logged in, so multiple accounts tested on one device don't
  /// collide and one user's multiple devices stay distinguishable.
  static Future<String> getDeviceId() async {
    var deviceId = await _storage.read(key: _deviceIdStorageKey);
    if (deviceId == null || deviceId.isEmpty) {
      final random = Random.secure();
      final bytes = List<int>.generate(16, (_) => random.nextInt(256));
      deviceId = base64UrlEncode(bytes);
      await _storage.write(key: _deviceIdStorageKey, value: deviceId);
    }
    return deviceId;
  }

  static Future<Map<String, String>> ensureIdentity(String userId) async {
    var privateKey = await _storage.read(key: _privateKeyStorageKey(userId));
    var publicKey = await _storage.read(key: _publicKeyStorageKey(userId));

    if (privateKey == null || publicKey == null) {
      final keyPair = await _keyAgreement.newKeyPair();
      final publicKeyObject = await keyPair.extractPublicKey();
      final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

      privateKey = base64Encode(privateKeyBytes);
      publicKey = base64Encode(publicKeyObject.bytes);

      await _storage.write(
          key: _privateKeyStorageKey(userId), value: privateKey);
      await _storage.write(key: _publicKeyStorageKey(userId), value: publicKey);
    }

    final resolvedPrivateKey = privateKey;
    final resolvedPublicKey = publicKey;

    // Cache the key pair in memory so _loadKeyPair works within this session
    // even when secure storage reads back null (e.g. after a fresh reinstall).
    _sessionKeyCache[userId] = SimpleKeyPairData(
      base64Decode(resolvedPrivateKey),
      publicKey: SimplePublicKey(
        base64Decode(resolvedPublicKey),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );

    await _registerPublicKey(resolvedPublicKey);

    return {
      'privateKey': resolvedPrivateKey,
      'publicKey': resolvedPublicKey,
    };
  }

  /// Returns every public key registered for [userId] across all of their
  /// devices, so a message can be encrypted for each one and decrypted on
  /// whichever device the recipient is currently using.
  static Future<List<String>> fetchUserPublicKeys(String userId) async {
    final response = await ApiClient.get('/api/users/$userId');
    if (response.statusCode != 200) return [];

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final devices = body['chatEncryptionDevices'];
    if (devices is List) {
      return devices
          .whereType<Map>()
          .map((d) => d['publicKey']?.toString() ?? '')
          .where((k) => k.isNotEmpty)
          .toSet()
          .toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> buildEncryptedEnvelope({
    required String senderId,
    required String plaintext,
    required Iterable<String> recipientIds,
    required Map<String, List<String>> publicKeysByUserId,
  }) async {
    final normalizedMessage = plaintext.trim();
    if (normalizedMessage.isEmpty) {
      throw Exception('Message cannot be empty.');
    }

    final identity = await ensureIdentity(senderId);
    final senderPublicKey = identity['publicKey']!;
    final senderKeyPair = await _loadKeyPair(senderId);

    final uniqueRecipientIds = <String>{...recipientIds};
    if (!uniqueRecipientIds.contains(senderId)) {
      uniqueRecipientIds.add(senderId);
    }

    final encryptedPayloads = <Map<String, dynamic>>[];

    for (final recipientUserId in uniqueRecipientIds) {
      final recipientPublicKeys = publicKeysByUserId[recipientUserId];
      if (recipientPublicKeys == null || recipientPublicKeys.isEmpty) {
        throw Exception(
            'Encrypted chat is not available for one of the participants yet.');
      }

      for (final recipientPublicKey in recipientPublicKeys) {
        final aesKey = await _deriveSharedAesKey(
          localKeyPair: senderKeyPair,
          remotePublicKeyBase64: recipientPublicKey,
          info: 'lenden-chat-v1',
        );

        final nonce = _aesGcm.newNonce();
        final secretBox = await _aesGcm.encrypt(
          utf8.encode(normalizedMessage),
          secretKey: aesKey,
          nonce: nonce,
        );

        encryptedPayloads.add({
          'recipientUserId': recipientUserId,
          'nonce': base64Encode(secretBox.nonce),
          'cipherText': base64Encode(secretBox.cipherText),
          'mac': base64Encode(secretBox.mac.bytes),
        });
      }
    }

    return {
      'senderPublicKey': senderPublicKey,
      'encryptionVersion': 1,
      'encryptedPayloads': encryptedPayloads,
    };
  }

  static Future<dynamic> decryptChat(
    dynamic rawChat, {
    required String currentUserId,
  }) async {
    if (rawChat is! Map) return rawChat;

    final chat = Map<String, dynamic>.from(rawChat);
    final encryptedPayloads = chat['encryptedPayloads'];
    final senderPublicKey = chat['senderPublicKey'];

    if (encryptedPayloads is List &&
        encryptedPayloads.isNotEmpty &&
        senderPublicKey is String &&
        senderPublicKey.isNotEmpty) {
      chat['message'] = await _decryptEnvelope(
        currentUserId: currentUserId,
        senderPublicKeyBase64: senderPublicKey,
        encryptedPayloads: encryptedPayloads,
      );
    } else {
      chat['message'] = ChatCodec.decodeMessage(chat['message']);
    }

    final parentMessage = chat['parentMessageId'];
    if (parentMessage is Map) {
      chat['parentMessageId'] = await decryptChat(
        Map<String, dynamic>.from(parentMessage),
        currentUserId: currentUserId,
      );
    }

    return chat;
  }

  static Future<void> _registerPublicKey(String publicKey) async {
    final deviceId = await getDeviceId();
    final response = await ApiClient.put(
      '/api/users/me/chat-public-key',
      body: {'chatEncryptionPublicKey': publicKey, 'deviceId': deviceId},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to register chat encryption key.');
    }
  }

  static Future<SimpleKeyPairData> _loadKeyPair(String userId) async {
    // Use the in-memory cached pair first — this is always populated by
    // ensureIdentity and survives even when secure storage reads fail.
    if (_sessionKeyCache.containsKey(userId)) {
      return _sessionKeyCache[userId]!;
    }

    final privateKey = await _storage.read(key: _privateKeyStorageKey(userId));
    final publicKey = await _storage.read(key: _publicKeyStorageKey(userId));

    if (privateKey == null || publicKey == null) {
      throw Exception('Encrypted chat is not initialized on this device.');
    }

    final kp = SimpleKeyPairData(
      base64Decode(privateKey),
      publicKey: SimplePublicKey(
        base64Decode(publicKey),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );
    _sessionKeyCache[userId] = kp;
    return kp;
  }

  static Future<SecretKey> _deriveSharedAesKey({
    required SimpleKeyPairData localKeyPair,
    required String remotePublicKeyBase64,
    required String info,
  }) async {
    final remotePublicKey = SimplePublicKey(
      base64Decode(remotePublicKeyBase64),
      type: KeyPairType.x25519,
    );

    final sharedSecret = await _keyAgreement.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remotePublicKey,
    );

    return _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(_hkdfNonce),
      info: utf8.encode(info),
    );
  }

  static Future<String> _decryptEnvelope({
    required String currentUserId,
    required String senderPublicKeyBase64,
    required List<dynamic> encryptedPayloads,
  }) async {
    final matchingPayloads = encryptedPayloads
        .whereType<Map>()
        .where((item) => item['recipientUserId']?.toString() == currentUserId)
        .toList();

    if (matchingPayloads.isEmpty) {
      return '[Encrypted message unavailable]';
    }

    SimpleKeyPairData? localKeyPair;
    try {
      localKeyPair = await _loadKeyPair(currentUserId);
    } catch (_) {
      return '[Encrypted message unavailable on this device]';
    }

    final aesKey = await _deriveSharedAesKey(
      localKeyPair: localKeyPair,
      remotePublicKeyBase64: senderPublicKeyBase64,
      info: 'lenden-chat-v1',
    );

    // The sender may have encrypted one payload per device key this user has
    // registered; try each until the one matching this device's key succeeds.
    for (final payload in matchingPayloads) {
      try {
        final secretBox = SecretBox(
          base64Decode(payload['cipherText'].toString()),
          nonce: base64Decode(payload['nonce'].toString()),
          mac: Mac(base64Decode(payload['mac'].toString())),
        );

        final clearBytes = await _aesGcm.decrypt(
          secretBox,
          secretKey: aesKey,
        );

        return utf8.decode(clearBytes);
      } catch (_) {
        continue;
      }
    }

    return '[Encrypted message unavailable on this device]';
  }
}
