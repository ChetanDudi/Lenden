import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../session.dart';
import '../admin/notifications/notifications_page.dart';
import '../user/notifications/notifications_page.dart';
import '../utils/api_client.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';
import '../services/sound_service.dart';

class NotificationIcon extends StatefulWidget {
  @override
  _NotificationIconState createState() => _NotificationIconState();
}

class _NotificationIconState extends State<NotificationIcon> {
  int _notificationCount = 0;
  int _prevUnreadCount = 0;
  bool _displayNotificationCount = true;
  bool _notificationSound = true;
  bool _vibrationEnabled = true;
  int _friendRequestCount = 0;
  DateTime? _lastFetched;
  Timer? _refreshTimer;
  static const _cacheDuration = Duration(seconds: 30);
  static const _pollInterval = Duration(minutes: 2);

  int get _combinedUserCount => _notificationCount + _friendRequestCount;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(_pollInterval, (_) {
      _lastFetched = null;
      _fetchUnreadNotificationCount();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final now = DateTime.now();
    if (_lastFetched == null || now.difference(_lastFetched!) > _cacheDuration) {
      _fetchUnreadNotificationCount();
    }
  }

  Future<void> _fetchUnreadNotificationCount() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.token == null) return;

    try {
      final responses = await Future.wait([
        ApiClient.get('/api/notifications/unread-count'),
        ApiClient.get(
          session.isAdmin
              ? '/api/admin/notification-settings'
              : '/api/users/notification-settings',
        ),
        if (!session.isAdmin) ApiClient.get('/api/friends/requests'),
      ]);

      final unreadResp = responses[0];
      final settingsResp = responses[1];

      if (unreadResp.statusCode == 200) {
        final data = json.decode(unreadResp.body);
        _notificationCount = data['count'] ?? 0;
      }

      if (settingsResp.statusCode == 200) {
        final settings = json.decode(settingsResp.body);
        _displayNotificationCount =
            settings['displayNotificationCount'] ?? true;
        _notificationSound = settings['notificationSound'] ?? true;
        _vibrationEnabled = settings['vibrationEnabled'] ?? true;
      }

      SoundService.update(sound: _notificationSound);
      if (_notificationCount > _prevUnreadCount) {
        if (_vibrationEnabled) HapticFeedback.lightImpact();
        SoundService.playNotification();
      }
      _prevUnreadCount = _notificationCount;

      if (!session.isAdmin && responses.length > 2) {
        final reqRes = responses[2];
        if (reqRes.statusCode == 200) {
          final data = json.decode(reqRes.body);
          _friendRequestCount = (data['incoming'] as List? ?? []).length;
        }
      } else {
        _friendRequestCount = 0;
      }

      _lastFetched = DateTime.now();
      if (mounted) setState(() {});
    } catch (e) {
      // Handle error
    }
  }

  /// Called externally (e.g. after returning from notifications page) to force
  /// an immediate refresh, bypassing the 30-second cache.
  void invalidateCache() {
    _lastFetched = null;
    _fetchUnreadNotificationCount();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (context, session, _) => Stack(
        children: [
          IconButton(
            icon: Icon(Icons.notifications_none,
                color: AppThemeColors.primaryText(context)),
            onPressed: () async {
              if (session.token != null && session.user != null) {
                if (session.isAdmin) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AdminNotificationsPage(),
                    ),
                  );
                } else {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const UserNotificationsPage(),
                    ),
                  );
                }
                await _fetchUnreadNotificationCount();
              } else {
                showDialog(
                  context: context,
                  builder: (dialogContext) {
                    final t = AppLocalizations.of(dialogContext).t;
                    return AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      backgroundColor: AppThemeColors.cardBg(dialogContext),
                      elevation: 12,
                      title: Row(
                        children: [
                          Icon(Icons.lock_outline,
                              color: AppColors.cyan, size: 28),
                          const SizedBox(width: 10),
                          Text(t('login_required'),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                  color: AppThemeColors.primaryText(
                                      dialogContext))),
                        ],
                      ),
                      content: Text(
                        t('please_login_to_view_notifications'),
                        style: TextStyle(
                            fontSize: 16,
                            color: AppThemeColors.secondaryText(dialogContext)),
                      ),
                      actions: [
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: AppColors.cyan,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 6),
                            child: Text(t('ok'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ),
                      ],
                    );
                  },
                );
              }
            },
          ),
          if (((session.isAdmin ? _notificationCount : _combinedUserCount) >
                  0) &&
              _displayNotificationCount)
            Positioned(
              right: 11,
              top: 11,
              child: Container(
                padding: EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(6),
                ),
                constraints: BoxConstraints(
                  minWidth: 14,
                  minHeight: 14,
                ),
                child: Text(
                  '${session.isAdmin ? _notificationCount : _combinedUserCount}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
