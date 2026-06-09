import 'dart:convert';

class ChatCodec {
  static const String _prefix = 'ldchat:';

  static String encodeMessage(String value) {
    return '$_prefix${base64Encode(utf8.encode(value))}';
  }

  static String decodeMessage(dynamic value) {
    if (value is! String || !value.startsWith(_prefix)) {
      return value?.toString() ?? '';
    }

    try {
      return utf8.decode(base64Decode(value.substring(_prefix.length)));
    } catch (_) {
      return value;
    }
  }

  static dynamic decodeChat(dynamic rawChat) {
    if (rawChat is! Map) return rawChat;

    final chat = Map<String, dynamic>.from(rawChat as Map);
    final message = chat['message'];
    if (message != null) {
      chat['message'] = decodeMessage(message);
    }

    final parentMessage = chat['parentMessageId'];
    if (parentMessage is Map) {
      chat['parentMessageId'] =
          decodeChat(Map<String, dynamic>.from(parentMessage));
    }

    return chat;
  }
}
