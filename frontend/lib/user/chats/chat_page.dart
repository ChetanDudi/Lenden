import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../api_config.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/wave_widget.dart';
import 'chat_encryption_service.dart';
import '../../widgets/app_widgets.dart';

class ChatPage extends StatefulWidget {
  final String transactionId;
  final String otherUserId;

  const ChatPage({
    Key? key,
    required this.transactionId,
    required this.otherUserId,
  }) : super(key: key);

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
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
  Map<String, dynamic>? _otherUser;
  String? _currentUserPublicKey;
  bool _encryptionReady = false;
  String? _encryptionError;

  void _showEncryptionUnavailableMessage() {
    if (!mounted) return;
    showSnack(context, 'Encrypted chat is not ready for this user yet. They need to open the updated app once before messages can be sent.', isError: true);
  }

  @override
  void initState() {
    super.initState();
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    _currentUserId = user?['_id'];
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
      await _fetchOtherUserDetails();
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

  Future<void> _fetchDailyMessageLimit() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.isSubscribed) return;
    try {
      final res = await ApiClient.get(
          '/api/limits/transaction/${widget.transactionId}/messages');
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

  Future<void> _fetchOtherUserDetails() async {
    try {
      final response = await ApiClient.get('/api/users/${widget.otherUserId}');
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _otherUser = jsonDecode(response.body);
          });
        }
      }
    } catch (e) {
      // Handle error
    }
  }

  void _initSocket() {
    socket = IO.io(ApiConfig.baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    socket.connect();
    socket.onConnect((_) {
      socket.emit('join', _currentUserId);
    });

    socket.on('newMessage', (data) async {
      final chat = await ChatEncryptionService.decryptChat(
        data['chat'],
        currentUserId: _currentUserId ?? '',
      );
      final messageCounts = data['messageCounts'];
      if (chat['transactionId'] == widget.transactionId) {
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

    socket.on('createMessageError', (data) {
      final errorText = (data['error'] ?? '').toString();
      if (errorText.toLowerCase().contains('daily limit')) {
        showDailyLimitDialog(context, message: errorText);
      } else if (errorText.toLowerCase().contains('total limit')) {
        showTotalLimitDialog(context, message: errorText);
      } else if (errorText.contains('Insufficient LenDen coins')) {
        showInsufficientCoinsDialog(context);
      }
    });

    socket.on('messageUpdated', (data) async {
      final decodedMessage = await ChatEncryptionService.decryptChat(
        data,
        currentUserId: _currentUserId ?? '',
      );
      if (decodedMessage['transactionId'] == widget.transactionId) {
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

    socket.on('messageDeleted', (data) {
      if (data['transactionId'] == widget.transactionId) {
        if (mounted) {
          setState(() {
            _messages.removeWhere((m) => m['_id'] == data['messageId']);
          });
        }
      }
    });
  }

  bool _withinEditWindow(dynamic message) {
    try {
      final created = DateTime.parse((message['createdAt'] ?? '').toString());
      return DateTime.now().difference(created).inMinutes < 2;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    socket.disconnect();
    socket.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    try {
      final response = await ApiClient.get(
          '/api/chat/messages/${widget.transactionId}?userId=$_currentUserId');
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

    final session = Provider.of<SessionProvider>(context, listen: false);
    final dailyLimitReached =
        !session.isSubscribed && _dailyMessageUsed >= _dailyMessageLimit;
    final remainingFree = 5 - (_messageCounts[_currentUserId] ?? 0);
    const int messageCost = 5;

    if (!session.isSubscribed) {
      // Daily limit expired → hard block; free messages also paused until tomorrow.
      if (dailyLimitReached) {
        showDailyLimitDialog(context,
            message:
                'You\'ve sent $_dailyMessageLimit messages today (daily limit). Free messages are also paused until tomorrow.\n\nSubscribe for unlimited chat.');
        return;
      }

      // Daily limit OK but total free messages exhausted → offer coins.
      if (remainingFree <= 0) {
        await session.loadFreebieCounts();
        final coins = session.lenDenCoins ?? 0;
        if (coins < messageCost) {
          coins == 0 ? showZeroCoinsDialog(context) : showInsufficientCoinsDialog(context);
          return;
        }
        final useCoins = await showFreeAttemptsExhaustedDialog(
          context,
          featureName: 'chat message',
          coinCost: messageCost,
          currentCoins: coins,
        );
        if (useCoins != true) return;
      }
    }

    if (_editingMessage != null) {
      await _editMessage();
      return;
    }

    await _fetchOtherUserDetails();
    final otherUserPublicKey =
        _otherUser?['chatEncryptionPublicKey']?.toString();
    if (otherUserPublicKey == null || otherUserPublicKey.isEmpty) {
      _showEncryptionUnavailableMessage();
      return;
    }

    final encryptedEnvelope = await ChatEncryptionService.buildEncryptedEnvelope(
      senderId: _currentUserId!,
      plaintext: _messageController.text.trim(),
      recipientIds: [_currentUserId!, widget.otherUserId],
      publicKeysByUserId: {
        _currentUserId!: _currentUserPublicKey ?? '',
        widget.otherUserId: otherUserPublicKey,
      },
    );

    socket.emit('createMessage', {
      'transactionId': widget.transactionId,
      'senderId': _currentUserId,
      'receiverId': widget.otherUserId,
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

    await _fetchOtherUserDetails();
    final otherUserPublicKey =
        _otherUser?['chatEncryptionPublicKey']?.toString();
    if (otherUserPublicKey == null || otherUserPublicKey.isEmpty) {
      _showEncryptionUnavailableMessage();
      return;
    }

    final encryptedEnvelope = await ChatEncryptionService.buildEncryptedEnvelope(
      senderId: _currentUserId!,
      plaintext: _messageController.text.trim(),
      recipientIds: [_currentUserId!, widget.otherUserId],
      publicKeysByUserId: {
        _currentUserId!: _currentUserPublicKey ?? '',
        widget.otherUserId: otherUserPublicKey,
      },
    );

    final message = {
      'messageId': _editingMessage['_id'],
      'userId': _currentUserId,
      'senderPublicKey': encryptedEnvelope['senderPublicKey'],
      'encryptionVersion': encryptedEnvelope['encryptionVersion'],
      'encryptedPayloads': encryptedEnvelope['encryptedPayloads'],
    };

    socket.emit('editMessage', message);

    _messageController.clear();
    setState(() {
      _editingMessage = null;
    });
  }

  void _deleteMessage(String messageId, bool forEveryone) {
    final message = {
      'messageId': messageId,
      'userId': _currentUserId,
      'forEveryone': forEveryone,
    };

    socket.emit('deleteMessage', message);
  }

  void _addReaction(String messageId, String emoji) {
    final message = {
      'messageId': messageId,
      'userId': _currentUserId,
      'emoji': emoji,
    };

    socket.emit('addReaction', message);
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
                if (isMe && _withinEditWindow(message))
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
                ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: Text('Delete for me'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _deleteMessage(message['_id'], false);
                  },
                ),
                if (isMe)
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

  void _showMessageCounts() {
    final currentUserMessageCount = _messageCounts[_currentUserId] ?? 0;
    final otherUserMessageCount = _messageCounts[widget.otherUserId] ?? 0;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [AppColors.cyan, Color(0xFF0077B6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.forum_outlined, color: AppColors.cyan),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: const Text(
                              'Total messages (lifetime)',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Column(
                      children: [
                        _buildCountRow(
                          'You',
                          currentUserMessageCount,
                          userId: _currentUserId,
                          gender: Provider.of<SessionProvider>(context,
                                  listen: false)
                              .user?['gender']
                              ?.toString(),
                        ),
                        const SizedBox(height: 10),
                        _buildCountRow(
                          _otherUser!['name'] ?? 'User',
                          otherUserMessageCount,
                          userId: widget.otherUserId,
                          gender: _otherUser?['gender']?.toString(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close',
                          style: TextStyle(
                              color: AppColors.cyan,
                              fontWeight: FontWeight.w700)),
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

  Widget _buildCountRow(String label, int count,
      {String? userId, String? gender}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7FB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.cyan.withValues(alpha: 0.18),
            child: ClipOval(
              child: _buildUserNetworkAvatar(
                userId: userId,
                gender: gender,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 10),
          Text('$count',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.cyan)),
        ],
      ),
    );
  }

  Widget _buildOtherUserAvatar() {
    return _buildUserNetworkAvatar(
      userId: _otherUser?['_id']?.toString(),
      gender: _otherUser?['gender']?.toString(),
      size: 40,
    );
  }

  Widget _buildUserNetworkAvatar({
    required String? userId,
    String? gender,
    double size = 40,
  }) {
    final fallbackAsset =
        'assets/${gender == 'Male' ? 'Male' : gender == 'Female' ? 'Female' : 'Other'}.png';
    if (userId == null || userId.isEmpty) {
      return Image.asset(fallbackAsset, width: size, height: size, fit: BoxFit.cover);
    }
    return Image.network(
      '${ApiConfig.baseUrl}/api/users/$userId/profile-image',
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          Image.asset(fallbackAsset, width: size, height: size, fit: BoxFit.cover),
    );
  }

  Widget _buildMessageCountChip() {
    final myCount = _messageCounts[_currentUserId] ?? 0;
    final otherCount = _messageCounts[widget.otherUserId] ?? 0;
    final total = myCount + otherCount;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _showMessageCounts,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              '$total',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_encryptionError != null) {
      return Scaffold(
        appBar: AppBar(title: Text('Chat')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Encrypted chat could not be initialized.\n$_encryptionError',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_isLoading && !_encryptionReady) {
      return Scaffold(
        backgroundColor: AppColors.cyan,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              const Text(
                'Initializing encrypted chat...',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_showEmojiPicker,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop && _showEmojiPicker) {
          setState(() {
            _showEmojiPicker = false;
          });
        }
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(140.0),
          child: AppBar(
            flexibleSpace: ClipPath(
              clipper: const TopWaveClipper(),
              child: Container(
                height: 140,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.cyan, Color(0xFF48CAE4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            title: _otherUser == null
                ? const Text('Chat',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold))
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 21,
                          backgroundColor: Colors.white,
                          child: ClipOval(child: _buildOtherUserAvatar()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _otherUser!['name'] ?? 'User',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Consumer<SessionProvider>(
                              builder: (context, session, child) {
                                if (session.isSubscribed) {
                                  return const SizedBox.shrink();
                                }
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.timer_outlined,
                                        size: 12, color: Colors.white70),
                                    SizedBox(width: 4),
                                    Text(
                                      'Daily message limit: 3',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
            actions: [
              _buildMessageCountChip(),
              const SizedBox(width: 8),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      reverse: true,
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages.reversed.toList()[index];
                        final sender = message['senderId'];
                        final isMe =
                            sender is Map && sender['_id'] == _currentUserId;
                        return _buildMessageBubble(message, isMe);
                      },
                    ),
            ),
            if (_replyingTo != null) _buildReplyingToBanner(),
            if (_editingMessage != null) _buildEditingBanner(),
            _buildDailyLimitPill(),
            _buildMessageInput(),
            if (_showEmojiPicker) _buildEmojiPicker(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(dynamic message, bool isMe) {
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

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (message['parentMessageId'] != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(bottom: 4),
              constraints: const BoxConstraints(maxWidth: 260),
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: const Border(
                    left: BorderSide(color: AppColors.cyan, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      'Replying to ${message['parentMessageId']['senderId']['name']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppColors.cyan)),
                  Text(message['parentMessageId']['message'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54)),
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
                  icon: const Icon(Icons.more_vert,
                      color: Colors.grey, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _showContextMenu(context, message, isMe),
                ),
              Flexible(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: EdgeInsets.fromLTRB(
                          14, 10, 14, hasReactions ? 22 : 10),
                      decoration: BoxDecoration(
                        gradient: isMe
                            ? const LinearGradient(
                                colors: [AppColors.cyan, Color(0xFF0096C7)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isMe ? null : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(isMe ? 18 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 18),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.07),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Text(
                            message['message'],
                            style: TextStyle(
                                color: isMe ? Colors.white : Colors.black87,
                                fontSize: 15.5,
                                height: 1.3),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(formattedTimestamp,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: isMe
                                          ? Colors.white70
                                          : Colors.black45,
                                      fontWeight: FontWeight.w500)),
                              if (message['isEdited'] == true)
                                Text(' · edited',
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontStyle: FontStyle.italic,
                                        color: isMe
                                            ? Colors.white70
                                            : Colors.black45)),
                            ],
                          ),
                        ],
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
                                  color: Colors.black.withValues(alpha: 0.15),
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
                  icon: const Icon(Icons.more_vert,
                      color: Colors.grey, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD9ECF2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
                _showEmojiPicker
                    ? Icons.close
                    : Icons.emoji_emotions_outlined,
                color: AppColors.cyan),
            onPressed: _onEmojiIconPressed,
          ),
          Expanded(
            child: TextField(
              focusNode: _messageFocusNode,
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message',
                hintStyle: TextStyle(color: Colors.grey.shade500),
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
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.cyan, Color(0xFF0096C7)],
                ),
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 18),
            ),
            onPressed: _sendMessage,
          ),
        ],
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
        color: const Color(0xFFEAF7FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 16, color: AppColors.cyan),
          const SizedBox(width: 6),
          Text(
            'Daily: $_dailyMessageUsed/$_dailyMessageLimit',
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: Color(0xFF086788)),
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
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7FB),
        borderRadius: BorderRadius.circular(14),
        border: const Border(
            left: BorderSide(color: AppColors.cyan, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Replying to ${(_replyingTo['senderId'] is Map ? _replyingTo['senderId']['name'] : '')}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppColors.cyan)),
                const SizedBox(height: 2),
                Text(_replyingTo['message'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
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
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(14),
        border: const Border(
            left: BorderSide(color: Color(0xFFF59E0B), width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Editing message',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Color(0xFFB45309))),
                const SizedBox(height: 2),
                Text(_editingMessage['message'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
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
}

