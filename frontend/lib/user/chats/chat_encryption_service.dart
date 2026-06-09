import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../utils/api_client.dart';
import 'chat_codec.dart';

class ChatEncryptionService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static final X25519 _keyAgreement = X25519();
  static final AesGcm _aesGcm = AesGcm.with256bits();
  static final Hkdf _hkdf =
      Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static const String _keyNamespace = 'chat_identity';
  static const String _hkdfNonce = 'LenDen-E2EE';

  static String _privateKeyStorageKey(String userId) =>
      '$_keyNamespace:${userId}:private';

  static String _publicKeyStorageKey(String userId) =>
      '$_keyNamespace:${userId}:public';

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

    final resolvedPrivateKey = privateKey!;
    final resolvedPublicKey = publicKey!;

    await _registerPublicKey(resolvedPublicKey);

    return {
      'privateKey': resolvedPrivateKey,
      'publicKey': resolvedPublicKey,
    };
  }

  static Future<String?> fetchUserPublicKey(String userId) async {
    final response = await ApiClient.get('/api/users/$userId');
    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final publicKey = body['chatEncryptionPublicKey'];
    if (publicKey is String && publicKey.isNotEmpty) {
      return publicKey;
    }
    return null;
  }

  static Future<Map<String, dynamic>> buildEncryptedEnvelope({
    required String senderId,
    required String plaintext,
    required Iterable<String> recipientIds,
    required Map<String, String> publicKeysByUserId,
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
      final recipientPublicKey = publicKeysByUserId[recipientUserId];
      if (recipientPublicKey == null || recipientPublicKey.isEmpty) {
        throw Exception(
            'Encrypted chat is not available for one of the participants yet.');
      }

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

    final chat = Map<String, dynamic>.from(rawChat as Map);
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
    final response = await ApiClient.put(
      '/api/users/me/chat-public-key',
      body: {'chatEncryptionPublicKey': publicKey},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to register chat encryption key.');
    }
  }

  static Future<SimpleKeyPairData> _loadKeyPair(String userId) async {
    final privateKey = await _storage.read(key: _privateKeyStorageKey(userId));
    final publicKey = await _storage.read(key: _publicKeyStorageKey(userId));

    if (privateKey == null || publicKey == null) {
      throw Exception('Encrypted chat is not initialized on this device.');
    }

    return SimpleKeyPairData(
      base64Decode(privateKey),
      publicKey: SimplePublicKey(
        base64Decode(publicKey),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );
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
    dynamic payload;
    for (final item in encryptedPayloads) {
      if (item is Map && item['recipientUserId']?.toString() == currentUserId) {
        payload = item;
        break;
      }
    }

    if (payload is! Map) {
      return '[Encrypted message unavailable]';
    }

    try {
      final localKeyPair = await _loadKeyPair(currentUserId);
      final aesKey = await _deriveSharedAesKey(
        localKeyPair: localKeyPair,
        remotePublicKeyBase64: senderPublicKeyBase64,
        info: 'lenden-chat-v1',
      );

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
      return '[Encrypted message unavailable on this device]';
    }
  }
}
