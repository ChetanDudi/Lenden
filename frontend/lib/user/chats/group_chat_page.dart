import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../api_config.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:intl/intl.dart';
import 'dart:math';
import '../../widgets/subscription_prompt.dart';
import '../../utils/api_client.dart';
import '../../widgets/stylish_dialog.dart';
import 'chat_encryption_service.dart';

class GroupChatPage extends StatefulWidget {
  final String groupTransactionId;
  final String groupTitle;
  final List<dynamic> members;

  const GroupChatPage({
    Key? key,
    required this.groupTransactionId,
    required this.groupTitle,
    required this.members,
  }) : super(key: key);

  @override
  _GroupChatPageState createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  List<dynamic> _messages = [];
  Map<String, int> _messageCounts = {};
  int _dailyMessageUsed = 0;
  int _dailyMessageLimit = 3;
  bool _isLoading = true;
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  String? _currentUserId;
  bool _showEmojiPicker = false;
  dynamic _replyingTo;
  dynamic _editingMessage;
  late IO.Socket socket;
  Map<String, Color> _userColors = {};
  final Random _random = Random();
  bool _isActiveMember = true;
  String? _currentUserPublicKey;
  final Map<String, String> _memberPublicKeys = {};
  bool _encryptionReady = false;
  String? _encryptionError;

  void _showEncryptionUnavailableMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Encrypted group chat is not ready for all members yet. Everyone needs to open the updated app once before messages can be sent.',
        ),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 4),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    _currentUserId = user?['_id'];

    for (var i = 0; i < widget.members.length; i++) {
      final member = widget.members[i];
      final memberId = _extractMemberId(member);
      if (memberId != null && !_userColors.containsKey(memberId)) {
        _userColors[memberId] = _getNoteColor(i);
      }
    }

    _initializeEncryptedChat();
  }

  Future<void> _initializeEncryptedChat() async {
    try {
      if (_currentUserId == null) {
        throw Exception('User session not found.');
      }

      final identity =
          await ChatEncryptionService.ensureIdentity(_currentUserId!);
      _currentUserPublicKey = identity['publicKey'];
      _memberPublicKeys[_currentUserId!] = _currentUserPublicKey!;
      await _loadMemberPublicKeys();
      await _fetchMessages();
      await _fetchDailyMessageLimit();
      _initSocket();

      if (mounted) {
        setState(() {
          _encryptionReady = true;
          _encryptionError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _encryptionReady = false;
          _encryptionError = error.toString();
        });
      }
    }
  }

  String? _extractMemberId(dynamic member) {
    if (member is! Map) return member?.toString();

    final directId = member['_id']?.toString();
    if (directId != null && directId.isNotEmpty) return directId;

    final nestedUser = member['user'];
    if (nestedUser is Map) {
      final nestedId = nestedUser['_id']?.toString();
      if (nestedId != null && nestedId.isNotEmpty) return nestedId;
    }

    final nestedUserId = nestedUser?.toString();
    if (nestedUserId != null && nestedUserId.isNotEmpty) return nestedUserId;

    return null;
  }

  Future<void> _loadMemberPublicKeys() async {
    final memberIds = <String>{};
    for (final member in widget.members) {
      if (member is Map && member['leftAt'] != null) continue;

      final memberId = _extractMemberId(member);

      if (memberId != null && memberId.isNotEmpty) {
        memberIds.add(memberId);
      }
    }

    for (final memberId in memberIds) {
      if (_memberPublicKeys.containsKey(memberId)) continue;
      final publicKey = await ChatEncryptionService.fetchUserPublicKey(memberId);
      if (publicKey != null && publicKey.isNotEmpty) {
        _memberPublicKeys[memberId] = publicKey;
      }
    }
  }

  Future<void> _fetchDailyMessageLimit() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.isSubscribed) return;
    try {
      final res = await ApiClient.get(
          '/api/limits/group/${widget.groupTransactionId}/messages');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _dailyMessageLimit = data['limit'] ?? 3;
            _dailyMessageUsed = data['used'] ?? 0;
          });
        }
      }
    } catch (_) {}
  }

  Color _getUserColor(String userId) {
    if (!_userColors.containsKey(userId)) {
      _userColors[userId] = _getNoteColor(_userColors.length);
    }
    return _userColors[userId]!;
  }

  Color _getNoteColor(int index) {
    final colors = [
      Color(0xFFFFF4E6), // Cream
      Color(0xFFE8F5E9), // Light green
      Color(0xFFFCE4EC), // Light pink
      Color(0xFFE3F2FD), // Light blue
      Color(0xFFFFF9C4), // Light yellow
      Color(0xFFF3E5F5), // Light purple
      Color(0xFFE0F2F1), // Light teal
      Color(0xFFFFF3E0), // Light orange
      Color(0xFFF1F8E9), // Light lime
      Color(0xFFE8EAF6), // Light indigo
    ];
    return colors[index % colors.length];
  }

  void _initSocket() {
    socket = IO.io(ApiConfig.baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    socket.connect();
    socket.onConnect((_) {
      socket.emit('joinGroup', widget.groupTransactionId);
    });

    socket.on('newGroupMessage', (data) async {
      final chat = await ChatEncryptionService.decryptChat(
        data['chat'],
        currentUserId: _currentUserId ?? '',
      );
      final messageCounts = data['messageCounts'];
      if (chat['groupTransactionId'] == widget.groupTransactionId) {
        if (!_messages.any((m) => m['_id'] == chat['_id'])) {
          if (mounted) {
            setState(() {
              _messages.add(chat);
              if (messageCounts != null) {
                for (var item in messageCounts) {
                  _messageCounts[item['user']['_id']] = item['count'];
                }
              }
              if (!Provider.of<SessionProvider>(context, listen: false)
                      .isSubscribed &&
                  chat['senderId']?['_id'] == _currentUserId) {
                _dailyMessageUsed = (_dailyMessageUsed + 1);
              }
            });
            if (data['lenDenCoins'] != null) {
              final session =
                  Provider.of<SessionProvider>(context, listen: false);
              session.loadFreebieCounts();
              _fetchDailyMessageLimit();
            }
          }
        }
      }
    });

    socket.on('createGroupMessageError', (data) {
      final errorText = (data['error'] ?? '').toString();
      if (errorText.toLowerCase().contains('daily limit')) {
        showDailyLimitDialog(context, message: errorText);
      } else if (errorText.toLowerCase().contains('total limit')) {
        showTotalLimitDialog(context, message: errorText);
      } else if (errorText.contains('Insufficient LenDen coins')) {
        showInsufficientCoinsDialog(context);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['error'] ?? 'Failed to send message'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    });

    socket.on('groupMessageUpdated', (data) async {
      final decodedMessage = await ChatEncryptionService.decryptChat(
        data,
        currentUserId: _currentUserId ?? '',
      );
      if (decodedMessage['groupTransactionId'] == widget.groupTransactionId) {
        final index =
            _messages.indexWhere((m) => m['_id'] == decodedMessage['_id']);
        if (index != -1) {
          if (mounted) {
            setState(() {
              _messages[index] = decodedMessage;
            });
          }
        }
      }
    });

    socket.on('groupMessageDeleted', (data) {
      if (data['groupTransactionId'] == widget.groupTransactionId) {
        if (mounted) {
          setState(() {
            _messages.removeWhere((m) => m['_id'] == data['messageId']);
          });
        }
      }
    });

    socket.on('editGroupMessageError', (data) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Failed to edit message'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });

    socket.on('deleteGroupMessageError', (data) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Failed to delete message'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });

    socket.on('addGroupReactionError', (data) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Failed to add reaction'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    socket.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    try {
      final response = await ApiClient.get(
          '/api/group-chat/messages/${widget.groupTransactionId}?userId=$_currentUserId');
      if (response.statusCode == 200) {
        if (mounted) {
          final body = jsonDecode(response.body);
          final decryptedMessages = <dynamic>[];
          for (final message in (body['messages'] as List<dynamic>)) {
            decryptedMessages.add(await ChatEncryptionService.decryptChat(
              message,
              currentUserId: _currentUserId ?? '',
            ));
          }
          setState(() {
            _messages = decryptedMessages;
            final messageCounts = body['messageCounts'];
            if (messageCounts != null) {
              for (var item in messageCounts) {
                _messageCounts[item['user']['_id']] = item['count'];
              }
            }
            _isLoading = false;
            _isActiveMember = true;
          });
        }
      } else if (response.statusCode == 403) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isActiveMember = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    if (!_encryptionReady || _currentUserId == null) return;

    if (!_isActiveMember) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'You are no longer an active member of this group. Chat is disabled.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final session = Provider.of<SessionProvider>(context, listen: false);
    final dailyLimitReached =
        !session.isSubscribed && _dailyMessageUsed >= _dailyMessageLimit;

    // Allow if subscribed OR free messages remaining
    final remainingFree = 5 - (_messageCounts[_currentUserId] ?? 0);
    const int messageCost = 7;

    if (!session.isSubscribed && (dailyLimitReached || remainingFree <= 0)) {
      final coins = session.lenDenCoins ?? 0;
      if (coins < messageCost) {
        if (coins == 0) {
          showZeroCoinsDialog(context);
        } else {
          showInsufficientCoinsDialog(context);
        }
        return;
      }

      final reasonText = dailyLimitReached
          ? 'Daily limit reached. Would you like to use $messageCost LenDen coins to send this message?'
          : 'You have no free messages remaining. Would you like to use $messageCost LenDen coins to send this message?';

      final useCoins = await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.monetization_on, color: Colors.orange, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Use LenDen Coins',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    reasonText,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'OR',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Subscribe now for unlimited access',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[300],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                              color: Colors.grey[800],
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context, false);
                          showSubscriptionPrompt(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                        child: Text(
                          'Subscribe',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                      SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                        child: Text(
                          'Use Coins',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (useCoins != true) {
        return;
      }
    }

    if (_editingMessage != null) {
      await _editMessage();
      return;
    }

    await _loadMemberPublicKeys();
    final activeRecipientIds = <String>{_currentUserId!};
    for (final member in widget.members) {
      if (member is Map && member['leftAt'] != null) continue;
      final memberId = _extractMemberId(member);
      if (memberId != null && memberId.isNotEmpty) {
        activeRecipientIds.add(memberId);
      }
    }

    final missingMembers = activeRecipientIds
        .where((id) => (_memberPublicKeys[id] ?? '').isEmpty)
        .toList();
    if (missingMembers.isNotEmpty) {
      await _loadMemberPublicKeys();
      final stillMissingMembers = activeRecipientIds
          .where((id) => (_memberPublicKeys[id] ?? '').isEmpty)
          .toList();
      if (stillMissingMembers.isNotEmpty) {
        _showEncryptionUnavailableMessage();
        return;
      }
    }

    final encryptedEnvelope = await ChatEncryptionService.buildEncryptedEnvelope(
      senderId: _currentUserId!,
      plaintext: _messageController.text.trim(),
      recipientIds: activeRecipientIds,
      publicKeysByUserId: _memberPublicKeys,
    );

    socket.emit('createGroupMessage', {
      'groupTransactionId': widget.groupTransactionId,
      'senderId': _currentUserId,
      'senderPublicKey': encryptedEnvelope['senderPublicKey'],
      'encryptionVersion': encryptedEnvelope['encryptionVersion'],
      'encryptedPayloads': encryptedEnvelope['encryptedPayloads'],
      'parentMessageId': _replyingTo?['_id'],
    });

    _messageController.clear();
    setState(() {
      _replyingTo = null;
    });
  }

  Future<void> _editMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    if (_currentUserId == null) return;

    await _loadMemberPublicKeys();
    final activeRecipientIds = <String>{_currentUserId!};
    for (final member in widget.members) {
      if (member is Map && member['leftAt'] != null) continue;
      final memberId = _extractMemberId(member);
      if (memberId != null && memberId.isNotEmpty) {
        activeRecipientIds.add(memberId);
      }
    }

    final stillMissingMembers = activeRecipientIds
        .where((id) => (_memberPublicKeys[id] ?? '').isEmpty)
        .toList();
    if (stillMissingMembers.isNotEmpty) {
      await _loadMemberPublicKeys();
      final unresolvedMembers = activeRecipientIds
          .where((id) => (_memberPublicKeys[id] ?? '').isEmpty)
          .toList();
      if (unresolvedMembers.isNotEmpty) {
        _showEncryptionUnavailableMessage();
        return;
      }
    }

    final encryptedEnvelope = await ChatEncryptionService.buildEncryptedEnvelope(
      senderId: _currentUserId!,
      plaintext: _messageController.text.trim(),
      recipientIds: activeRecipientIds,
      publicKeysByUserId: _memberPublicKeys,
    );

    final message = {
      'messageId': _editingMessage['_id'],
      'userId': _currentUserId,
      'senderPublicKey': encryptedEnvelope['senderPublicKey'],
      'encryptionVersion': encryptedEnvelope['encryptionVersion'],
      'encryptedPayloads': encryptedEnvelope['encryptedPayloads'],
    };

    socket.emit('editGroupMessage', message);

    _messageController.clear();
    setState(() {
      _editingMessage = null;
    });
  }

  void _showMembersDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: const Color(0xFFFAF9F6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFAF9F6),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with tricolor border
                  Container(
                    padding: const EdgeInsets.all(20.0),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.orange, Colors.white, Colors.green],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(22),
                        topRight: Radius.circular(22),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.group, color: Colors.black87, size: 28),
                        SizedBox(width: 12),
                        Text(
                          'Group Members',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Spacer(),
                        IconButton(
                          icon: Container(
                            padding: EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.close,
                                color: Colors.black87, size: 20),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  // Members list with tricolor borders
                  Container(
                    constraints: BoxConstraints(maxHeight: 400),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: widget.members.length,
                      itemBuilder: (context, index) {
                        final member = widget.members[index];
                        final memberId = _extractMemberId(member);
                        final messageCount = _messageCounts[memberId] ?? 0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              colors: [
                                Colors.orange,
                                Colors.white,
                                Colors.green
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: _getNoteColor(
                                  index + 1), // Unique color for each member
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              leading: CircleAvatar(
                                backgroundColor:
                                    _getUserColor(memberId ?? member['email'])
                                        .withOpacity(0.8),
                                child: Text(
                                  (member['email'] ?? 'U')[0].toUpperCase(),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                member['email'] ?? 'Unknown',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              subtitle: Text(
                                'Total messages (lifetime): $messageCount',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                              trailing: member['leftAt'] != null
                                  ? Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Left',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Active',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Footer
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      '${widget.members.length} members',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _onEmojiIconPressed() {
    if (_showEmojiPicker) {
      _messageFocusNode.requestFocus();
    } else {
      _messageFocusNode.unfocus();
    }
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });
  }

  void _deleteMessage(String messageId, bool forEveryone) {
    final message = {
      'messageId': messageId,
      'userId': _currentUserId,
      'forEveryone': forEveryone,
    };

    socket.emit('deleteGroupMessage', message);
  }

  void _addReaction(String messageId, String emoji) {
    final message = {
      'messageId': messageId,
      'userId': _currentUserId,
      'emoji': emoji,
    };

    socket.emit('addGroupReaction', message);
  }

  void _showReactionPicker(String messageId) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Container(
            height: 300,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Expanded(
                  child: EmojiPicker(
                    onEmojiSelected: (category, emoji) {
                      Navigator.of(context).pop();
                      _addReaction(messageId, emoji.emoji);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMessageInfo(dynamic message) {
    final createdAt = DateTime.parse(message['createdAt']).toLocal();
    final formattedDate = DateFormat.yMMMMd().format(createdAt);
    final formattedTime = DateFormat.jm().format(createdAt);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [Colors.blue.shade200, Colors.blue.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child:
                      Icon(Icons.info_outline, color: Colors.white, size: 40),
                ),
                Text(
                  'Message Details',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    children: [
                      _buildInfoRow(
                          Icons.calendar_today, 'Date', formattedDate),
                      SizedBox(height: 8),
                      _buildInfoRow(Icons.access_time, 'Time', formattedTime),
                    ],
                  ),
                ),
                SizedBox(height: 24),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('CLOSE',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        SizedBox(width: 16),
        Text(
          '$label:',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_encryptionError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.groupTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Encrypted group chat could not be initialized.\n$_encryptionError',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        if (_showEmojiPicker) {
          setState(() {
            _showEmojiPicker = false;
          });
          return false;
        }
        return true;
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: const Color(0xFFFAF9F6),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.groupTitle,
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
              Consumer<SessionProvider>(
                builder: (context, session, child) {
                  if (session.isSubscribed) {
                    return SizedBox.shrink();
                  }
                  return Text(
                    'Daily message limit: 3',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  );
                },
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.more_vert, color: Colors.black),
              onPressed: _showMembersDialog,
            )
          ],
        ),
        body: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClipPath(
                clipper: TopWaveClipper(),
                child: Container(
                  height: 120,
                  color: const Color(0xFF00B4D8),
                ),
              ),
            ),
            Column(
              children: [
                SizedBox(height: 120),
                Expanded(
                  child: _isLoading
                      ? Center(child: CircularProgressIndicator())
                      : _isActiveMember
                          ? ListView.builder(
                              reverse: true,
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final message =
                                    _messages.reversed.toList()[index];
                                final sender = message['senderId'];
                                final isMe = sender is Map &&
                                    sender['_id'] == _currentUserId;
                                return _buildMessageBubble(
                                    message, isMe, index);
                              },
                            )
                          : _buildInactiveMemberWidget(),
                ),
                if (_isActiveMember)
                  if (_replyingTo != null) _buildReplyingToBanner(),
                if (_isActiveMember)
                  if (_editingMessage != null) _buildEditingBanner(),
                if (_isActiveMember) _buildDailyLimitPill(),
                if (_isActiveMember) _buildMessageInput(),
                if (_isActiveMember)
                  if (_showEmojiPicker) _buildEmojiPicker(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInactiveMemberWidget() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_accounts,
                size: 60, color: Colors.red.withOpacity(0.8)),
            const SizedBox(height: 20),
            Text(
              'You are no longer a member of this group.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Chat is disabled.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(dynamic message, bool isMe, int index) {
    if (message['createdAt'] == null) {
      return const SizedBox.shrink();
    }
    final createdAt = DateTime.parse(message['createdAt']).toLocal();
    final now = DateTime.now();
    final isToday = createdAt.day == now.day &&
        createdAt.month == now.month &&
        createdAt.year == now.year;

    String formattedTimestamp;
    if (isToday) {
      formattedTimestamp = DateFormat.jm().format(createdAt);
    } else {
      formattedTimestamp = DateFormat('MMM d, yyyy, h:mm a').format(createdAt);
    }
    final hasReactions =
        message['reactions'] != null && message['reactions'].isNotEmpty;
    final senderName = message['senderId']?['name'] ?? 'Unknown';
    final senderId = message['senderId']?['_id'] ?? 'unknown';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 12.0, bottom: 4.0),
              child: Text(
                senderName,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          if (message['parentMessageId'] != null)
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Replying to ${message['parentMessageId']?['senderId']?['name'] ?? ''}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.black54)),
                  Text(message['parentMessageId']?['message'] ?? '',
                      style: TextStyle(color: Colors.black54)),
                ],
              ),
            ),
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe)
                IconButton(
                  icon: Icon(Icons.more_vert, color: Colors.grey),
                  onPressed: () => _showContextMenu(context, message, isMe),
                ),
              Flexible(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(17),
                        gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.white, Colors.green],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Container(
                        padding: EdgeInsets.fromLTRB(
                            12, 10, 12, hasReactions ? 25 : 10),
                        decoration: BoxDecoration(
                          color: isMe
                              ? const Color(0xFFE8F5E9)
                              : _getUserColor(senderId),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Text(
                              message['message'],
                              style:
                                  TextStyle(color: Colors.black, fontSize: 16),
                            ),
                            SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(formattedTimestamp,
                                    style: TextStyle(
                                        fontSize: 10, color: Colors.black54)),
                                if (message['isEdited'] == true)
                                  Text(' (edited)',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.black54)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (hasReactions)
                      Positioned(
                        bottom: -12,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 3, horizontal: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 4,
                                  offset: Offset(0, 1))
                            ],
                          ),
                          child: Wrap(
                            spacing: 5,
                            children:
                                message['reactions'].map<Widget>((reaction) {
                              return Text(reaction['emoji'],
                                  style: TextStyle(fontSize: 14));
                            }).toList(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (isMe)
                IconButton(
                  icon: Icon(Icons.more_vert, color: Colors.grey),
                  onPressed: () => _showContextMenu(context, message, isMe),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(27),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      margin: EdgeInsets.all(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                  _showEmojiPicker
                      ? Icons.close
                      : Icons.emoji_emotions_outlined,
                  color: Colors.grey),
              onPressed: _onEmojiIconPressed,
            ),
            Expanded(
              child: TextField(
                focusNode: _messageFocusNode,
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message',
                  border: InputBorder.none,
                ),
                onTap: () {
                  if (_showEmojiPicker) {
                    setState(() {
                      _showEmojiPicker = false;
                    });
                  }
                },
              ),
            ),
            IconButton(
              icon: Icon(Icons.send, color: Colors.blue),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyLimitPill() {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.isSubscribed) return SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, size: 16, color: Colors.blue),
          const SizedBox(width: 6),
          Text(
            'Daily: $_dailyMessageUsed/$_dailyMessageLimit',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiPicker() {
    return EmojiPicker(
      onEmojiSelected: (category, emoji) {
        _messageController.text += emoji.emoji;
      },
      onBackspacePressed: () {
        _messageController.text =
            _messageController.text.characters.skipLast(1).toString();
      },
    );
  }

  Widget _buildReplyingToBanner() {
    return Container(
      padding: EdgeInsets.all(8),
      color: Colors.grey[200],
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Replying to ${(_replyingTo['senderId'] is Map ? _replyingTo['senderId']['name'] : '')}',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(_replyingTo['message'],
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: () {
              setState(() {
                _replyingTo = null;
              });
            },
          )
        ],
      ),
    );
  }

  Widget _buildEditingBanner() {
    return Container(
      padding: EdgeInsets.all(8),
      color: Colors.grey[200],
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Editing message',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(_editingMessage['message'],
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: () {
              setState(() {
                _editingMessage = null;
                _messageController.clear();
              });
            },
          )
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context, dynamic message, bool isMe) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15.0),
            ),
            child: Wrap(
              children: <Widget>[
                if (isMe &&
                    _isActiveMember &&
                    DateTime.now()
                            .difference(DateTime.parse(message['createdAt']))
                            .inMinutes <
                        2)
                  ListTile(
                    leading: Icon(Icons.edit, color: Colors.blueAccent),
                    title: Text('Edit'),
                    onTap: () {
                      Navigator.of(context).pop();
                      setState(() {
                        _editingMessage = message;
                        _messageController.text = message['message'];
                        _messageFocusNode.requestFocus();
                      });
                    },
                  ),
                if (_isActiveMember)
                  ListTile(
                    leading: Icon(Icons.reply, color: Colors.greenAccent),
                    title: Text('Reply'),
                    onTap: () {
                      Navigator.of(context).pop();
                      setState(() {
                        _replyingTo = message;
                        _messageFocusNode.requestFocus();
                      });
                    },
                  ),
                if (_isActiveMember)
                  ListTile(
                    leading: Icon(Icons.emoji_emotions_outlined,
                        color: Colors.orangeAccent),
                    title: Text('React'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showReactionPicker(message['_id']);
                    },
                  ),
                ListTile(
                  leading: Icon(Icons.info_outline, color: Colors.grey),
                  title: Text('Info'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showMessageInfo(message);
                  },
                ),
                if (_isActiveMember)
                  ListTile(
                    leading:
                        Icon(Icons.delete_outline, color: Colors.redAccent),
                    title: Text('Delete for me'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _deleteMessage(message['_id'], false);
                    },
                  ),
                if (isMe && _isActiveMember)
                  ListTile(
                    leading:
                        Icon(Icons.delete_forever_outlined, color: Colors.red),
                    title: Text('Delete for everyone'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _deleteMessage(message['_id'], true);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height * 0.7);
    path.quadraticBezierTo(
        size.width * 0.25, size.height, size.width * 0.5, size.height * 0.7);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.4, size.width, size.height * 0.7);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
