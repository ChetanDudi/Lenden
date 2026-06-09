import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../api_config.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:intl/intl.dart';
import '../../widgets/subscription_prompt.dart';
import '../../utils/api_client.dart';
import '../../widgets/stylish_dialog.dart';
import 'chat_encryption_service.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Encrypted chat is not ready for this user yet. They need to open the updated app once before messages can be sent.',
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

    // Allow if subscribed OR free messages remaining
    final remainingFree = 5 - (_messageCounts[_currentUserId] ?? 0);
    const int messageCost = 5;

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

      // Ask user whether to use coins or subscribe
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

    final otherUserPublicKey =
        _otherUser?['chatEncryptionPublicKey']?.toString();
    if (otherUserPublicKey == null || otherUserPublicKey.isEmpty) {
      await _fetchOtherUserDetails();
      final refreshedPublicKey =
          _otherUser?['chatEncryptionPublicKey']?.toString();
      if (refreshedPublicKey == null || refreshedPublicKey.isEmpty) {
        _showEncryptionUnavailableMessage();
        return;
      }
      final encryptedEnvelope =
          await ChatEncryptionService.buildEncryptedEnvelope(
        senderId: _currentUserId!,
        plaintext: _messageController.text.trim(),
        recipientIds: [_currentUserId!, widget.otherUserId],
        publicKeysByUserId: {
          _currentUserId!: _currentUserPublicKey ?? '',
          widget.otherUserId: refreshedPublicKey,
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
    final otherUserPublicKey =
        _otherUser?['chatEncryptionPublicKey']?.toString();
    if (_currentUserId == null ||
        otherUserPublicKey == null ||
        otherUserPublicKey.isEmpty) {
      await _fetchOtherUserDetails();
      final refreshedPublicKey =
          _otherUser?['chatEncryptionPublicKey']?.toString();
      if (refreshedPublicKey == null || refreshedPublicKey.isEmpty) {
        _showEncryptionUnavailableMessage();
        return;
      }

      final encryptedEnvelope =
          await ChatEncryptionService.buildEncryptedEnvelope(
        senderId: _currentUserId!,
        plaintext: _messageController.text.trim(),
        recipientIds: [_currentUserId!, widget.otherUserId],
        publicKeysByUserId: {
          _currentUserId!: _currentUserPublicKey ?? '',
          widget.otherUserId: refreshedPublicKey,
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
                if (isMe &&
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
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Total messages (lifetime)',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCE4EC),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('You:',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              Text('$currentUserMessageCount',
                                  style: TextStyle(fontSize: 16)),
                            ],
                          ),
                        ),
                        SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCE4EC),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${_otherUser!['name']}:',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              Text('$otherUserMessageCount',
                                  style: TextStyle(fontSize: 16)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(120.0),
          child: AppBar(
            flexibleSpace: ClipPath(
              clipper: WaveClipper(),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Colors.blue.shade400, Colors.blue.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                ),
              ),
            ),
            title: _otherUser == null
                ? Text('Chat')
                : Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.white,
                        child: ClipOval(
                          child: (_otherUser!['profileImage'] != null)
                              ? Image.network(
                                  '${ApiConfig.baseUrl}/api/users/${_otherUser!['_id']}/profile-image',
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    final gender =
                                        _otherUser?['gender'] ?? 'Other';
                                    if (gender == 'Male') {
                                      return Image.asset('assets/Male.png');
                                    } else if (gender == 'Female') {
                                      return Image.asset('assets/Female.png');
                                    } else {
                                      return Image.asset('assets/Other.png');
                                    }
                                  },
                                )
                              : Image.asset(
                                  'assets/${_otherUser?['gender'] == 'Male' ? 'Male' : _otherUser?['gender'] == 'Female' ? 'Female' : 'Other'}.png',
                                ),
                        ),
                      ),
                      SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_otherUser!['name'] ?? 'User'),
                          Consumer<SessionProvider>(
                            builder: (context, session, child) {
                              if (session.isSubscribed) {
                                return SizedBox.shrink();
                              }
                              return Text(
                                'Daily message limit: 3',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.white70),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'message_count') {
                    _showMessageCounts();
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'message_count',
                    child: Text('Message Count'),
                  ),
                ],
              ),
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
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
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
                      'Replying to ${message['parentMessageId']['senderId']['name']}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.black54)),
                  Text(message['parentMessageId']['message'],
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
                          color: isMe ? Color(0xFFE8F5E9) : Color(0xFFE3F2FD),
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
}

class WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height * 0.525); // 0.7 * 0.75
    path.quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.75, // 1.0 * 0.75
        size.width * 0.5,
        size.height * 0.525); // 0.7 * 0.75
    path.quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.3, // 0.4 * 0.75
        size.width,
        size.height * 0.525); // 0.7 * 0.75
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
