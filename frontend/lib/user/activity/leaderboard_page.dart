import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'package:provider/provider.dart';
import '../../api_config.dart';
import '../../utils/api_client.dart';
import '../../session.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final Map<String, List<dynamic>> _rowsByType = {
    'quick': [],
    'group': [],
    'trxns': [],
  };
  final Set<String> _friendIds = {};
  final Set<String> _incomingRequestUserIds = {};
  final Set<String> _outgoingRequestUserIds = {};
  final Set<String> _submittingFriendIds = {};

  bool _loading = true;
  bool _friendsOnly = false;
  String _activeType = 'quick';
  String _range = 'daily';
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      final type = _typeFromIndex(_tabController.index);
      if (_activeType != type) {
        setState(() => _activeType = type);
        _loadLeaderboard();
      }
    });
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _typeFromIndex(int index) {
    if (index == 0) return 'quick';
    if (index == 1) return 'group';
    return 'trxns';
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadLeaderboard(),
      _loadFriendState(),
    ]);
  }

  Future<void> _loadFriendState() async {
    try {
      final responses = await Future.wait([
        ApiClient.get('/api/friends'),
        ApiClient.get('/api/friends/requests'),
      ]);

      final friendsRes = responses[0];
      final requestsRes = responses[1];

      if (!mounted) return;

      final nextFriendIds = <String>{};
      final nextIncomingIds = <String>{};
      final nextOutgoingIds = <String>{};

      if (friendsRes.statusCode == 200) {
        final data = jsonDecode(friendsRes.body);
        final friends = List<Map<String, dynamic>>.from(data['friends'] ?? []);
        for (final friend in friends) {
          final id = friend['_id']?.toString();
          if (id != null && id.isNotEmpty) nextFriendIds.add(id);
        }
      }

      if (requestsRes.statusCode == 200) {
        final data = jsonDecode(requestsRes.body);
        final incoming =
            List<Map<String, dynamic>>.from(data['incoming'] ?? []);
        final outgoing =
            List<Map<String, dynamic>>.from(data['outgoing'] ?? []);

        for (final request in incoming) {
          final id = request['from']?['_id']?.toString();
          if (id != null && id.isNotEmpty) nextIncomingIds.add(id);
        }
        for (final request in outgoing) {
          final id = request['to']?['_id']?.toString();
          if (id != null && id.isNotEmpty) nextOutgoingIds.add(id);
        }
      }

      setState(() {
        _friendIds
          ..clear()
          ..addAll(nextFriendIds);
        _incomingRequestUserIds
          ..clear()
          ..addAll(nextIncomingIds);
        _outgoingRequestUserIds
          ..clear()
          ..addAll(nextOutgoingIds);
      });
    } catch (_) {
      // Keep leaderboard usable even if friend-state lookups fail.
    }
  }

  Future<void> _sendFriendRequest(dynamic row) async {
    final userId = row?['userId']?.toString();
    if (_isCurrentUser(row) ||
        userId == null ||
        userId.isEmpty ||
        _submittingFriendIds.contains(userId)) {
      return;
    }

    setState(() => _submittingFriendIds.add(userId));
    try {
      final res =
          await ApiClient.post('/api/friends/request', body: {'userId': userId});

      if (!mounted) return;

      if (res.statusCode == 200 || res.statusCode == 201) {
        final t = AppLocalizations.of(context).t;
        final data = jsonDecode(res.body);
        final message = (data['message'] ?? 'Request sent').toString();
        await _loadFriendState();
        if (!mounted) return;
        final rowName = (row['name'] ?? t('this_user_label')).toString();
        _showStylishMessage(
          title: t('friend_request_title'),
          message: message == 'Already friends'
              ? '$rowName ${t('already_in_friends_list_msg')}'
              : message == 'Request already pending'
                  ? '${t('friend_request_pending_for_msg')} $rowName.'
                  : '${t('friend_request_sent_to_msg')} $rowName.',
          icon: message == 'Already friends'
              ? Icons.people_alt_rounded
              : Icons.person_add_alt_1_rounded,
          color: AppColors.cyan,
        );
      } else {
        final t = AppLocalizations.of(context).t;
        String message = t('could_not_send_friend_request_msg');
        try {
          final data = jsonDecode(res.body);
          final backendMessage =
              (data['error'] ?? data['message'])?.toString().trim();
          if (backendMessage != null && backendMessage.isNotEmpty) {
            message = backendMessage;
          }
        } catch (_) {}
        _showStylishMessage(
          title: t('unable_to_add_title'),
          message: message,
          icon: Icons.error_outline,
          color: Colors.redAccent,
        );
      }
    } catch (_) {
      if (!mounted) return;
      final t = AppLocalizations.of(context).t;
      _showStylishMessage(
        title: t('network_error'),
        message: t('could_not_send_friend_request_msg'),
        icon: Icons.wifi_off_rounded,
        color: Colors.redAccent,
      );
    } finally {
      if (mounted) {
        setState(() => _submittingFriendIds.remove(userId));
      }
    }
  }

  bool _isCurrentUser(dynamic row) {
    if (row?['isCurrentUser'] == true) return true;
    final myId = Provider.of<SessionProvider>(context, listen: false)
        .user?['_id']
        ?.toString();
    final myEmail = Provider.of<SessionProvider>(context, listen: false)
        .user?['email']
        ?.toString()
        .trim()
        .toLowerCase();
    final rowUserId = row?['userId']?.toString();
    final rowEmail = row?['email']?.toString().trim().toLowerCase();
    if (myId != null && myId.isNotEmpty && rowUserId == myId) return true;
    return myEmail != null &&
        myEmail.isNotEmpty &&
        rowEmail != null &&
        rowEmail.isNotEmpty &&
        rowEmail == myEmail;
  }

  String _friendActionLabel(dynamic row) {
    final t = AppLocalizations.of(context).t;
    final userId = row?['userId']?.toString();
    if (userId == null || userId.isEmpty || _isCurrentUser(row)) return '';
    if (_friendIds.contains(userId)) return t('friend_chip_label');
    if (_incomingRequestUserIds.contains(userId)) {
      return t('requested_you_chip_label');
    }
    if (_outgoingRequestUserIds.contains(userId)) {
      return t('requested_chip_label');
    }
    return '';
  }

  bool _canAddFriend(dynamic row) => _friendActionLabel(row).isEmpty;

  Future<void> _loadLeaderboard() async {
    setState(() => _loading = true);
    final path =
        '/api/leaderboard?type=$_activeType&range=$_range&friendsOnly=$_friendsOnly';
    final t = AppLocalizations.of(context).t;
    try {
      final res = await ApiClient.get(path);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final users = List<dynamic>.from(data['users'] ?? []);
        setState(() {
          _rowsByType[_activeType] = users;
          _fetchError = null;
          _loading = false;
        });
        if (users.isEmpty && mounted) {
          _showStylishMessage(
            title: t('no_rankings_yet_title'),
            message: t('no_rankings_yet_msg'),
            icon: Icons.info_outline,
            color: AppColors.cyan,
          );
        }
      } else {
        final msg = '${t('failed_to_load_leaderboard_msg')} (${res.statusCode}).';
        setState(() {
          _fetchError = msg;
          _loading = false;
        });
        if (mounted) {
          _showStylishMessage(
            title: t('load_failed_title'),
            message: msg,
            icon: Icons.error_outline,
            color: Colors.redAccent,
          );
        }
      }
    } catch (_) {
      final msg = t('unable_to_load_leaderboard_msg');
      setState(() {
        _fetchError = msg;
        _loading = false;
      });
      if (mounted) {
        _showStylishMessage(
          title: t('network_error'),
          message: msg,
          icon: Icons.wifi_off_rounded,
          color: Colors.redAccent,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final rows = _rowsByType[_activeType] ?? [];
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          t('leaderboard'),
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(context)),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          tabAlignment: TabAlignment.fill,
          labelPadding: EdgeInsets.zero,
          indicatorColor: AppColors.cyan,
          labelColor: AppColors.cyan,
          unselectedLabelColor: AppThemeColors.secondaryText(context),
          tabs: [
            Tab(text: t('lb_quick_tab')),
            Tab(text: t('lb_group_tab')),
            Tab(text: t('lb_secure_tab')),
          ],
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 150,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: AppThemeColors.waveGradient(context),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _fetchError != null
                    ? errorStateWidget(context, _fetchError!, _loadLeaderboard)
                    : rows.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.leaderboard_outlined, size: 72,
                                    color: AppThemeColors.divider(context)),
                                const SizedBox(height: 14),
                                Text(t('no_more_users_ranking_msg'),
                                    style: TextStyle(fontSize: 16,
                                        color: AppThemeColors.secondaryText(context)),
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: _loadLeaderboard,
                                  icon: const Icon(Icons.refresh_rounded, size: 18),
                                  label: Text(t('retry'),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 15)),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFF06322),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 36, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30)),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                    onRefresh: () async {
                      await _loadLeaderboard();
                      if (mounted && _fetchError == null) {
                        _showStylishMessage(
                          title: t('refreshed_title'),
                          message: t('leaderboard_updated_msg'),
                          icon: Icons.refresh,
                          color: AppColors.cyan,
                        );
                      }
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        _buildFilters(),
                        _buildMyPositionCard(rows),
                        _buildPodium(rows),
                        const SizedBox(height: 10),
                        _buildHintButtons(context),
                        const SizedBox(height: 12),
                        _buildTopList(rows),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyPositionCard(List<dynamic> rows) {
    final t = AppLocalizations.of(context).t;
    final myId = Provider.of<SessionProvider>(context, listen: false).user?['_id']?.toString();
    dynamic myRow;
    if (myId != null && myId.isNotEmpty) {
      for (final row in rows) {
        if (row['userId']?.toString() == myId) { myRow = row; break; }
      }
    }
    return _triBorderCard(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: myRow != null
              ? AppThemeColors.tinted(context,
                  light: const Color(0xFFE6F7FF), dark: const Color(0xFF163A42))
              : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: myRow != null ? Border.all(color: AppColors.cyan, width: 1.2) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.emoji_events_outlined, color: AppColors.cyan, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: myRow == null
                  ? Text(t('not_ranked_period_msg'),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppThemeColors.secondaryText(context)))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('your_position_label'),
                            style: TextStyle(
                                fontSize: 11,
                                color: AppThemeColors.secondaryText(context))),
                        const SizedBox(height: 2),
                        Text(
                          'Rank #${myRow['rank']} · ${myRow['points']} pts',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.cyan),
                        ),
                      ],
                    ),
            ),
            if (myRow != null) _movementWidget(myRow),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final t = AppLocalizations.of(context).t;
    return _triBorderCard(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'daily', label: Text(t('daily'))),
                ButtonSegment(value: 'weekly', label: Text(t('weekly'))),
                ButtonSegment(value: 'monthly', label: Text(t('monthly'))),
              ],
              selected: {_range},
              onSelectionChanged: (value) {
                final next = value.first;
                if (next == _range) return;
                setState(() => _range = next);
                _loadLeaderboard();
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.people_alt_outlined,
                    size: 18, color: Color(0xFF005F73)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t('friends_only_label'),
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppThemeColors.primaryText(context)),
                  ),
                ),
                Switch(
                  value: _friendsOnly,
                  activeColor: AppColors.cyan,
                  onChanged: (v) {
                    setState(() => _friendsOnly = v);
                    _loadLeaderboard();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPodium(List<dynamic> rows) {
    final first = rows.isNotEmpty ? rows[0] : null;
    final second = rows.length > 1 ? rows[1] : null;
    final third = rows.length > 2 ? rows[2] : null;
    return _triBorderCard(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _podiumPerson(second, 2, 30),
            _podiumPerson(first, 1, 40),
            _podiumPerson(third, 3, 30),
          ],
        ),
      ),
    );
  }

  Widget _podiumPerson(dynamic row, int fallbackRank, double radius) {
    final name = row?['name']?.toString() ?? '-';
    final points = row?['points']?.toString() ?? '0';
    final displayedRank = row?['rank'] is int ? row['rank'] as int : fallbackRank;
    final actionLabel = _friendActionLabel(row);
    final buttonLabel = _isCurrentUser(row)
        ? ''
        : actionLabel.isEmpty
            ? '+'
            : actionLabel;
    return SizedBox(
      width: 95,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_rankLabel(displayedRank),
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 4),
          _avatar(row, radius),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppThemeColors.primaryText(context)),
          ),
          const SizedBox(height: 2),
          Text('$points pts',
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4F5D75),
                  fontSize: 12)),
          const SizedBox(height: 2),
          _movementWidget(row),
          const SizedBox(height: 6),
          _buildFriendActionChip(
            row,
            compact: true,
            labelOverride: buttonLabel,
          ),
        ],
      ),
    );
  }

  Widget _buildHintButtons(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Center(
      child: ElevatedButton(
        onPressed: () {
          _showStylishMessage(
            title: t('how_points_work_title'),
            message: t('how_points_work_msg'),
            icon: Icons.stars_rounded,
            color: AppColors.cyan,
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4CC9F0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(t('how_to_earn_points_btn'), style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildTopList(List<dynamic> rows) {
    final t = AppLocalizations.of(context).t;
    final others = rows.length > 3 ? rows.sublist(3) : <dynamic>[];
    if (others.isEmpty) {
      return _triBorderCard(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Center(
            child: Text(
              t('no_more_users_ranking_msg'),
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppThemeColors.secondaryText(context)),
            ),
          ),
        ),
      );
    }

    return _triBorderCard(
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: others.map((row) {
            final isMe = _isCurrentUser(row);
            final breakdown = row['breakdown'] ?? {};
            final actionLabel = _friendActionLabel(row);
            final buttonLabel = isMe
                ? ''
                : actionLabel.isEmpty
                    ? t('add_plus_label')
                    : actionLabel;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? AppThemeColors.tinted(context,
                        light: const Color(0xFFE6F7FF), dark: const Color(0xFF163A42))
                    : AppThemeColors.tinted(context,
                        light: const Color(0xFFF1F5F9), dark: const Color(0xFF24272C)),
                border: isMe
                    ? Border.all(color: AppColors.cyan, width: 1.2)
                    : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('${row['rank']}',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppThemeColors.secondaryText(context))),
                      const SizedBox(width: 10),
                      _avatar(row, 14),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          row['name']?.toString() ?? t('unknown_user_label'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppThemeColors.primaryText(context)),
                        ),
                      ),
                      _movementWidget(row),
                      const SizedBox(width: 8),
                      _buildFriendActionChip(
                        row,
                        compact: false,
                        labelOverride: buttonLabel,
                      ),
                      if (buttonLabel.isNotEmpty) const SizedBox(width: 8),
                      Text('${row['points']} pts',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF4F5D75))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _chip('Q ${breakdown['quick'] ?? 0}'),
                      const SizedBox(width: 6),
                      _chip('${t('group_breakdown_label')} ${breakdown['group'] ?? 0}'),
                      const SizedBox(width: 6),
                      _chip('${t('trxns_breakdown_label')} ${breakdown['trxns'] ?? 0}'),
                      const SizedBox(width: 6),
                      _chip('${t('all_breakdown_label')} ${(breakdown['totalPoints'] ?? 0)} pts'),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFriendActionChip(
    dynamic row, {
    required bool compact,
    required String labelOverride,
  }) {
    final userId = row?['userId']?.toString() ?? '';
    final canAdd = _canAddFriend(row);
    final isLoading = _submittingFriendIds.contains(userId);
    final isFriend = _friendIds.contains(userId);

    if (labelOverride.isEmpty) {
      return const SizedBox.shrink();
    }

    if (isFriend) {
      return Container(
        width: compact ? 28 : null,
        height: compact ? 28 : null,
        padding: compact
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFEAFBF0),
          borderRadius: BorderRadius.circular(compact ? 999 : 10),
          border: Border.all(color: const Color(0xFF2EAF5D)),
        ),
        child: compact
            ? const Icon(
                Icons.check,
                size: 16,
                color: Color(0xFF2EAF5D),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check,
                    size: 14,
                    color: Color(0xFF2EAF5D),
                  ),
                ],
              ),
      );
    }

    if (!canAdd) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 6 : 5,
        ),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(compact ? 999 : 10),
          border: Border.all(color: const Color(0xFFD7DEE8)),
        ),
        child: Text(
          labelOverride,
          style: TextStyle(
            fontSize: compact ? 10 : 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF4F5D75),
          ),
        ),
      );
    }

    return compact
        ? SizedBox(
            width: 28,
            height: 28,
            child: OutlinedButton(
              onPressed: isLoading ? null : () => _sendFriendRequest(row),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: const BorderSide(color: AppColors.cyan),
                backgroundColor: AppThemeColors.cardBg(context),
                shape: const CircleBorder(),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      '+',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppColors.cyan,
                      ),
                    ),
            ),
          )
        : OutlinedButton(
            onPressed: isLoading ? null : () => _sendFriendRequest(row),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.cyan,
              backgroundColor: AppThemeColors.cardBg(context),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              side: const BorderSide(color: AppColors.cyan),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    labelOverride,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
          );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD7DEE8)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF4F5D75),
        ),
      ),
    );
  }

  Widget _movementWidget(dynamic row) {
    final movement = row?['movement'] ?? {};
    final direction = (movement['direction'] ?? 'same').toString();
    final delta = (movement['delta'] ?? 0) as int;

    IconData icon = Icons.horizontal_rule;
    Color color = AppThemeColors.secondaryText(context);
    String label = '0';
    if (direction == 'up') {
      icon = Icons.arrow_upward_rounded;
      color = Colors.green;
      label = '+$delta';
    } else if (direction == 'down') {
      icon = Icons.arrow_downward_rounded;
      color = Colors.redAccent;
      label = '-$delta';
    } else if (direction == 'new') {
      icon = Icons.fiber_new_rounded;
      color = AppColors.cyan;
      label = 'new';
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: Row(
        key: ValueKey('$direction-$delta'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _triBorderCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );
  }

  Widget _avatar(dynamic row, double radius) {
    final gender = (row?['gender'] ?? 'Other').toString();
    final userId = row?['userId']?.toString();
    final fallback = AssetImage(
      gender == 'Male'
          ? 'assets/Male.png'
          : gender == 'Female'
              ? 'assets/Female.png'
              : 'assets/Other.png',
    );

    if (userId == null || userId.isEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: fallback);
    }

    final url = '${ApiConfig.baseUrl}/api/users/$userId/profile-image';
    return Stack(
      alignment: Alignment.center,
      children: [
        CircleAvatar(radius: radius, backgroundImage: fallback),
        ClipOval(
          child: Image.network(
            url,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  String _rankLabel(int rank) {
    final mod100 = rank % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${rank}th';
    switch (rank % 10) {
      case 1:
        return '${rank}st';
      case 2:
        return '${rank}nd';
      case 3:
        return '${rank}rd';
      default:
        return '${rank}th';
    }
  }

  void _showStylishMessage({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
  }) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 42),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15,
                        color: AppThemeColors.secondaryText(context)),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(AppLocalizations.of(context).t('ok'),
                        style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
