import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../api_config.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/stylish_dialog.dart';
import '../../widgets/wave_widget.dart';
import 'chat_encryption_service.dart';
import '../../widgets/app_widgets.dart';

class GroupChatPage extends StatefulWidget {
  final String groupTransactionId;
  final String groupTitle;
  final List<dynamic> members;
  final String? groupImageUrl;

  const GroupChatPage({
    Key? key,
    required this.groupTransactionId,
    required this.groupTitle,
    required this.members,
    this.groupImageUrl,
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
  bool _isActiveMember = true;
  String? _currentUserPublicKey;
  final Map<String, List<String>> _memberPublicKeys = {};
  bool _encryptionReady = false;
  String? _encryptionError;
  String? _groupImageUrl;
  bool _isUpdatingGroupImage = false;
  final Set<String> _pendingMentionIds = {};
  bool _pendingMentionAll = false;

  void _showEncryptionUnavailableMessage() {
    if (!mounted) return;
    showSnack(context, 'Encrypted group chat is not ready for all members yet. Everyone needs to open the updated app once before messages can be sent.', isError: true);
  }

  @override
  void initState() {
    super.initState();
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    _currentUserId = user?['_id'];
    _groupImageUrl = widget.groupImageUrl;
    _initializeEncryptedChat();
  }

  Future<void> _pickAndUploadGroupImage() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image == null) return;

      setState(() => _isUpdatingGroupImage = true);
      final res = await ApiClient.putMultipart(
        '/api/group-transactions/${widget.groupTransactionId}/image',
        files: [
          ApiMultipartFile(
            field: 'groupImage',
            filename: 'group.jpg',
            path: image.path,
            contentType: MediaType('image', 'jpeg'),
          ),
        ],
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _groupImageUrl = data['groupImageUrl']?.toString();
        });
        showSnack(context, 'Group photo updated.');
      } else {
        showSnack(context, 'Could not update group photo.', isError: true);
      }
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Could not update group photo.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isUpdatingGroupImage = false);
    }
  }

  Future<void> _removeGroupImage() async {
    setState(() => _isUpdatingGroupImage = true);
    try {
      final res = await ApiClient.delete(
          '/api/group-transactions/${widget.groupTransactionId}/image');
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _groupImageUrl = null);
        showSnack(context, 'Group photo removed.');
      } else {
        showSnack(context, 'Could not remove group photo.', isError: true);
      }
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Could not remove group photo.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isUpdatingGroupImage = false);
    }
  }

  void _showGroupPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bc) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15.0),
          ),
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined,
                    color: AppColors.cyan),
                title: const Text('Change Group Photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickAndUploadGroupImage();
                },
              ),
              if (_groupImageUrl != null)
                ListTile(
                  leading:
                      const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text('Remove Group Photo'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _removeGroupImage();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initializeEncryptedChat() async {
    try {
      if (_currentUserId == null) {
        throw Exception('User session not found.');
      }

      final identity =
          await ChatEncryptionService.ensureIdentity(_currentUserId!);
      _currentUserPublicKey = identity['publicKey'];
      _memberPublicKeys[_currentUserId!] = [_currentUserPublicKey!];
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

  Future<void> _loadMemberPublicKeys({bool forceRefresh = false}) async {
    final memberIds = <String>{};
    if (_currentUserId != null) memberIds.add(_currentUserId!);
    for (final member in widget.members) {
      if (member is Map && member['leftAt'] != null) continue;

      final memberId = _extractMemberId(member);

      if (memberId != null && memberId.isNotEmpty) {
        memberIds.add(memberId);
      }
    }

    for (final memberId in memberIds) {
      if (!forceRefresh && _memberPublicKeys.containsKey(memberId)) continue;
      final publicKeys = await ChatEncryptionService.fetchUserPublicKeys(memberId);
      if (publicKeys.isNotEmpty) {
        _memberPublicKeys[memberId] = publicKeys;
      }
    }
  }

  Future<void> _fetchDailyMessageLimit() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.hasFeature('group_chat')) return;
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
            final senderId = chat['senderId'] is Map
                ? chat['senderId']['_id']?.toString()
                : null;
            final mentionsList = (chat['mentions'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [];
            final isMentioned = senderId != _currentUserId &&
                (chat['mentionsAll'] == true ||
                    mentionsList.contains(_currentUserId));
            if (isMentioned && mounted) {
              final senderName = chat['senderId'] is Map
                  ? (chat['senderId']['name'] ?? 'Someone').toString()
                  : 'Someone';
              showSnack(context, '$senderName mentioned you in the group');
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
          showSnack(context, data['error'] ?? 'Failed to send message', isError: true);
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
        showSnack(context, data['error'] ?? 'Failed to edit message', isError: true);
      }
    });

    socket.on('deleteGroupMessageError', (data) {
      if (mounted) {
        showSnack(context, data['error'] ?? 'Failed to delete message', isError: true);
      }
    });

    socket.on('addGroupReactionError', (data) {
      if (mounted) {
        showSnack(context, data['error'] ?? 'Failed to add reaction', isError: true);
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
      showSnack(context, 'You are no longer an active member of this group. Chat is disabled.', isError: true);
      return;
    }

    final session = Provider.of<SessionProvider>(context, listen: false);

    if (!session.hasFeature('group_chat')) {
      if (_dailyMessageUsed >= _dailyMessageLimit) {
        showDailyLimitDialog(context,
            message:
                'You\'ve sent $_dailyMessageLimit messages today in this group. '
                'Your free attempts are also paused. Come back tomorrow!');
        return;
      }
      final remainingFree = 5 - (_messageCounts[_currentUserId] ?? 0);
      if (remainingFree <= 0) {
        await session.loadFreebieCounts();
        final coins = session.lenDenCoins ?? 0;
        final useCoins = await showFreeAttemptsExhaustedDialog(context,
            featureName: 'group chat message', coinCost: session.groupChatCoinCost, currentCoins: coins);
        if (useCoins != true) return;
      }
    }

    if (_editingMessage != null) {
      await _editMessage();
      return;
    }

    await _loadMemberPublicKeys(forceRefresh: true);
    final activeRecipientIds = <String>{_currentUserId!};
    for (final member in widget.members) {
      if (member is Map && member['leftAt'] != null) continue;
      final memberId = _extractMemberId(member);
      if (memberId != null && memberId.isNotEmpty) {
        activeRecipientIds.add(memberId);
      }
    }

    final missingMembers = activeRecipientIds
        .where((id) => (_memberPublicKeys[id] ?? const <String>[]).isEmpty)
        .toList();
    if (missingMembers.isNotEmpty) {
      await _loadMemberPublicKeys();
      final stillMissingMembers = activeRecipientIds
          .where((id) => (_memberPublicKeys[id] ?? const <String>[]).isEmpty)
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
      'mentions': _pendingMentionAll ? [] : _pendingMentionIds.toList(),
      'mentionsAll': _pendingMentionAll,
    });

    _messageController.clear();
    setState(() {
      _replyingTo = null;
      _pendingMentionIds.clear();
      _pendingMentionAll = false;
    });
  }

  Future<void> _editMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    if (_currentUserId == null) return;

    await _loadMemberPublicKeys(forceRefresh: true);
    final activeRecipientIds = <String>{_currentUserId!};
    for (final member in widget.members) {
      if (member is Map && member['leftAt'] != null) continue;
      final memberId = _extractMemberId(member);
      if (memberId != null && memberId.isNotEmpty) {
        activeRecipientIds.add(memberId);
      }
    }

    final stillMissingMembers = activeRecipientIds
        .where((id) => (_memberPublicKeys[id] ?? const <String>[]).isEmpty)
        .toList();
    if (stillMissingMembers.isNotEmpty) {
      await _loadMemberPublicKeys();
      final unresolvedMembers = activeRecipientIds
          .where((id) => (_memberPublicKeys[id] ?? const <String>[]).isEmpty)
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
      if (_pendingMentionAll || _pendingMentionIds.isNotEmpty) ...{
        'mentions': _pendingMentionAll ? [] : _pendingMentionIds.toList(),
        'mentionsAll': _pendingMentionAll,
      },
    };

    socket.emit('editGroupMessage', message);

    _messageController.clear();
    _pendingMentionIds.clear();
    _pendingMentionAll = false;
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
              color: AppThemeColors.cardBg(context),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20.0),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.cyan, Color(0xFF0077B6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(22),
                        topRight: Radius.circular(22),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.groups_rounded,
                            color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        const Text(
                          'Group Members',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 20),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  // Members list
                  Container(
                    constraints: BoxConstraints(maxHeight: 400),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: widget.members.length,
                      itemBuilder: (context, index) {
                        final member = widget.members[index];
                        final memberId = _extractMemberId(member);
                        final displayName = _memberDisplayName(member);
                        final hasLeft = member['leftAt'] != null;
                        final avatarColor =
                            _avatarColorFor(memberId ?? displayName);
                        return _buildTricolorMemberBox(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            leading: _buildUserAvatar(
                              userId: memberId,
                              label: displayName,
                              fallbackColor: avatarColor,
                            ),
                            title: _buildHorizontalScrollText(
                              displayName,
                              TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppThemeColors.primaryText(context),
                              ),
                            ),
                            subtitle: Text(
                              'Member',
                              style: TextStyle(
                                color: AppThemeColors.secondaryText(context),
                                fontSize: 12,
                              ),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: (hasLeft ? Colors.red : Colors.green)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                hasLeft ? 'Left' : 'Active',
                                style: TextStyle(
                                  color: hasLeft ? Colors.red : Colors.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
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

  void _showMentionPicker() {
    final activeMembers = widget.members.where((m) {
      if (m is! Map) return true;
      if (m['leftAt'] != null) return false;
      final memberId = _extractMemberId(m);
      return memberId != _currentUserId;
    }).toList();

    final Set<String> selected = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bc) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(8.0),
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.65),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18.0),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Row(
                        children: [
                          Icon(Icons.alternate_email, color: AppColors.cyan),
                          SizedBox(width: 8),
                          Text('Tag Members',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    CheckboxListTile(
                      value: selected.contains('all'),
                      secondary: const CircleAvatar(
                        backgroundColor: AppColors.cyan,
                        child:
                            Icon(Icons.groups, color: Colors.white, size: 18),
                      ),
                      title: const Text('All',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      activeColor: AppColors.cyan,
                      onChanged: (v) {
                        setSheetState(() {
                          selected.clear();
                          if (v == true) selected.add('all');
                        });
                      },
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: activeMembers.length,
                        itemBuilder: (context, index) {
                          final member = activeMembers[index];
                          final memberId = _extractMemberId(member);
                          final displayName = _memberDisplayName(member);
                          final key = memberId ?? displayName;
                          final avatarColor = _avatarColorFor(key);
                          final allSelected = selected.contains('all');
                          return CheckboxListTile(
                            value: allSelected || selected.contains(key),
                            enabled: !allSelected,
                            activeColor: AppColors.cyan,
                            secondary: _buildUserAvatar(
                              userId: memberId,
                              label: displayName,
                              fallbackColor: avatarColor,
                              radius: 16,
                            ),
                            title: _buildHorizontalScrollText(
                              displayName,
                              const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            onChanged: (v) {
                              setSheetState(() {
                                if (v == true) {
                                  selected.add(key);
                                } else {
                                  selected.remove(key);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () {
                                  setState(() {
                                    if (selected.contains('all')) {
                                      _pendingMentionAll = true;
                                      _pendingMentionIds.clear();
                                    } else {
                                      for (final key in selected) {
                                        final member = activeMembers
                                            .firstWhere(
                                              (m) =>
                                                  (_extractMemberId(m) ??
                                                      _memberDisplayName(
                                                          m)) ==
                                                  key,
                                              orElse: () => null,
                                            );
                                        final id = member != null
                                            ? _extractMemberId(member)
                                            : null;
                                        if (id != null && id.isNotEmpty) {
                                          _pendingMentionIds.add(id);
                                        }
                                      }
                                    }
                                  });
                                  String mentionText;
                                  if (selected.contains('all')) {
                                    mentionText = '@All ';
                                  } else {
                                    mentionText = selected.map((key) {
                                      final member = activeMembers.firstWhere(
                                        (m) =>
                                            (_extractMemberId(m) ??
                                                _memberDisplayName(m)) ==
                                            key,
                                      );
                                      return '@${_memberDisplayName(member)} ';
                                    }).join();
                                  }
                                  final current = _messageController.text;
                                  final separator =
                                      current.isEmpty || current.endsWith(' ')
                                          ? ''
                                          : ' ';
                                  _messageController.text =
                                      '$current$separator$mentionText';
                                  _messageController.selection =
                                      TextSelection.collapsed(
                                          offset:
                                              _messageController.text.length);
                                  Navigator.of(context).pop();
                                  _messageFocusNode.requestFocus();
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text('Insert Tags'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<InlineSpan> _buildMentionSpans(String text, bool isMe) {
    final names = <String>{
      'All',
      ...widget.members.map((m) => _memberDisplayName(m)),
    }.where((n) => n.trim().isNotEmpty).toList();
    if (names.isEmpty) return [TextSpan(text: text)];

    names.sort((a, b) => b.length.compareTo(a.length));
    final pattern =
        RegExp('@(${names.map(RegExp.escape).join('|')})(?!\\w)');
    final spans = <InlineSpan>[];
    int last = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: isMe ? Colors.white : AppColors.cyan,
        ),
      ));
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return spans;
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

  static const List<Color> _avatarPalette = [
    Color(0xFFFFA726),
    Color(0xFF66BB6A),
    Color(0xFFEC407A),
    Color(0xFF42A5F5),
    Color(0xFFAB47BC),
    Color(0xFF26A69A),
    Color(0xFFFF7043),
    Color(0xFF9CCC65),
    Color(0xFF5C6BC0),
    Color(0xFF8D6E63),
  ];

  Color _avatarColorFor(String userId) {
    final hash = userId.hashCode.abs();
    return _avatarPalette[hash % _avatarPalette.length];
  }

  Widget _buildGroupMessageStatsChip() {
    final total = _messageCounts.values.fold<int>(0, (a, b) => a + b);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _showGroupMessageCounts,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, size: 16, color: Colors.black87),
            const SizedBox(width: 6),
            Text(
              '$total',
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _memberDisplayName(dynamic member) {
    if (member is Map) {
      final name = (member['name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
      final email = (member['email'] ?? '').toString().trim();
      if (email.isNotEmpty) return email;
    }
    return 'Unknown';
  }

  Widget _buildUserAvatar({
    required String? userId,
    required String label,
    required Color fallbackColor,
    double radius = 16,
  }) {
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: fallbackColor,
      child: Text(
        label.isNotEmpty ? label[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: radius * 0.68,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
    if (userId == null || userId.isEmpty) return fallback;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppThemeColors.cardBg(context),
      child: ClipOval(
        child: Image.network(
          '${ApiConfig.baseUrl}/api/users/$userId/profile-image',
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
      ),
    );
  }

  Widget _buildTricolorMemberBox({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      ),
    );
  }

  Widget _buildHorizontalScrollText(String text, TextStyle style) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Text(text, style: style),
    );
  }

  void _showGroupMessageCounts() {
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
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.forum_outlined,
                            color: AppColors.cyan),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildHorizontalScrollText(
                            'Total messages (lifetime)',
                            const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 360),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.members.length,
                      itemBuilder: (context, index) {
                        final member = widget.members[index];
                        final memberId = _extractMemberId(member);
                        final displayName = _memberDisplayName(member);
                        final messageCount = _messageCounts[memberId] ?? 0;
                        final avatarColor =
                            _avatarColorFor(memberId ?? displayName);
                        return _buildTricolorMemberBox(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4),
                            leading: _buildUserAvatar(
                              userId: memberId,
                              label: displayName,
                              fallbackColor: avatarColor,
                            ),
                            title: _buildHorizontalScrollText(
                              displayName,
                              const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            trailing: Text(
                              '$messageCount',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.cyan,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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
        extendBodyBehindAppBar: true,
        backgroundColor: AppThemeColors.scaffoldBg(context),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 0,
          title: Row(
            children: [
              GestureDetector(
                onTap: _showGroupPhotoOptions,
                child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: _groupImageUrl != null
                          ? Image.network(
                              _groupImageUrl!,
                              width: 42,
                              height: 42,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.groups_rounded,
                                      color: AppColors.cyan, size: 24),
                            )
                          : const Icon(Icons.groups_rounded,
                              color: AppColors.cyan, size: 24),
                    ),
                  ),
                  if (_isUpdatingGroupImage)
                    const Positioned.fill(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  Positioned(
                    top: -2,
                    left: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppColors.cyan,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt,
                          color: Colors.white, size: 10),
                    ),
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.cyan,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        '${widget.members.length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.groupTitle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppThemeColors.primaryText(context),
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                    Consumer<SessionProvider>(
                      builder: (context, session, child) {
                        if (session.hasFeature('group_chat')) {
                          return SizedBox.shrink();
                        }
                        return Text(
                          'Daily message limit: 3',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: AppThemeColors.secondaryText(context),
                              fontWeight: FontWeight.w600),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            _buildGroupMessageStatsChip(),
            const SizedBox(width: 4),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
                ),
                child: const Icon(Icons.group_outlined,
                    color: Colors.black87, size: 20),
              ),
              onPressed: _showMembersDialog,
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClipPath(
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
            ),
            Column(
              children: [
                SizedBox(height: 140),
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
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_accounts,
                size: 60, color: Colors.red.withValues(alpha: 0.8)),
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
    final _sRaw = (message['senderId']?['name'] ?? '').toString();
    final senderName = (_sRaw.isEmpty || RegExp(r'^[0-9a-f]{24}$').hasMatch(_sRaw)) ? 'Deleted Account' : _sRaw;
    final senderId = message['senderId']?['_id'] ?? 'unknown';

    final senderColor = _avatarColorFor(senderId);
    final mentionsList = (message['mentions'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final isMentionedHere = !isMe &&
        (message['mentionsAll'] == true ||
            mentionsList.contains(_currentUserId));

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
                      'Replying to ${() { final n = (message['parentMessageId']?['senderId']?['name'] ?? '').toString(); return (n.isEmpty || RegExp(r'^[0-9a-f]{24}$').hasMatch(n)) ? 'Deleted Account' : n; }()}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppColors.cyan)),
                  Text(message['parentMessageId']?['message'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: AppThemeColors.secondaryText(context))),
                ],
              ),
            ),
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                _buildUserAvatar(
                  userId: senderId == 'unknown' ? null : senderId.toString(),
                  label: senderName,
                  fallbackColor: senderColor,
                  radius: 14,
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.more_vert,
                      color: Colors.grey, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _showContextMenu(context, message, isMe),
                ),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (!isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                        child: Text(
                          senderName,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: senderColor),
                        ),
                      ),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: EdgeInsets.fromLTRB(
                              14, 10, 14, hasReactions ? 22 : 10),
                          decoration: BoxDecoration(
                            gradient: isMe
                                ? const LinearGradient(
                                    colors: [
                                      AppColors.cyan,
                                      Color(0xFF0096C7)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            color: isMe ? null : AppThemeColors.cardBg(context),
                            border: isMe
                                ? null
                                : Border.all(
                                    color: isMentionedHere
                                        ? Colors.amber
                                        : senderColor.withValues(alpha: 0.5),
                                    width: isMentionedHere ? 2 : 1,
                                  ),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(isMe ? 18 : 4),
                              bottomRight: Radius.circular(isMe ? 4 : 18),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
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
                              Text.rich(
                                TextSpan(
                                  children: _buildMentionSpans(
                                      message['message'].toString(), isMe),
                                  style: TextStyle(
                                      color: isMe
                                          ? Colors.white
                                          : AppThemeColors.primaryText(context),
                                      fontSize: 15.5,
                                      height: 1.3),
                                ),
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
                                              : AppThemeColors.mutedText(context),
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
                                      color: Colors.black
                                          .withValues(alpha: 0.15),
                                      blurRadius: 4,
                                      offset: Offset(0, 1))
                                ],
                              ),
                              child: Wrap(
                                spacing: 5,
                                children: message['reactions']
                                    .map<Widget>((reaction) {
                                  return Text(reaction['emoji'],
                                      style: TextStyle(fontSize: 14));
                                }).toList(),
                              ),
                            ),
                          ),
                      ],
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
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppThemeColors.border(context)),
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
          IconButton(
            icon: const Icon(Icons.alternate_email, color: AppColors.cyan),
            tooltip: 'Tag members',
            onPressed: _showMentionPicker,
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
    if (session.hasFeature('group_chat')) return SizedBox.shrink();
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
                    'Replying to ${() { final s = _replyingTo['senderId']; final n = s is Map ? (s['name'] ?? '').toString() : ''; return (n.isEmpty || RegExp(r'^[0-9a-f]{24}$').hasMatch(n)) ? 'Deleted Account' : n; }()}',
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

