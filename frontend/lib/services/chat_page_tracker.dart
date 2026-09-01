// Tracks which chat page (if any) the user is currently viewing so that
// FirebaseService can suppress foreground banners for the active conversation.
class ChatPageTracker {
  static String? _groupChatId;
  static String? _secureChatId;

  static void enterGroupChat(String id) => _groupChatId = id;
  static void exitGroupChat() => _groupChatId = null;

  static void enterSecureChat(String id) => _secureChatId = id;
  static void exitSecureChat() => _secureChatId = null;

  // Returns true only when the user is currently looking at this exact chat.
  static bool isOnGroupChat(String groupId) => _groupChatId == groupId;
  static bool isOnSecureChat(String txId) => _secureChatId == txId;
}
