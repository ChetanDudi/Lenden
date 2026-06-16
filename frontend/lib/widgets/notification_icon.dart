import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../session.dart';
import '../admin/notifications/notifications_page.dart';
import '../user/notifications/notifications_page.dart';
import '../utils/api_client.dart';

class NotificationIcon extends StatefulWidget {
  @override
  _NotificationIconState createState() => _NotificationIconState();
}

class _NotificationIconState extends State<NotificationIcon> {
  int _notificationCount = 0;
  bool _displayNotificationCount = true;
  int _friendRequestCount = 0;

  int get _combinedUserCount => _notificationCount + _friendRequestCount;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchUnreadNotificationCount();
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
      }

      if (!session.isAdmin && responses.length > 2) {
        final reqRes = responses[2];
        if (reqRes.statusCode == 200) {
          final data = json.decode(reqRes.body);
          _friendRequestCount = (data['incoming'] as List? ?? []).length;
        }
      } else {
        _friendRequestCount = 0;
      }

      if (mounted) setState(() {});
    } catch (e) {
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (context, session, _) => Stack(
        children: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.black),
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
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    backgroundColor: const Color(0xFFF6F7FB),
                    elevation: 12,
                    title: Row(
                      children: [
                        Icon(Icons.lock_outline,
                            color: AppColors.cyan, size: 28),
                        SizedBox(width: 10),
                        Text('Login Required',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 22)),
                      ],
                    ),
                    content: Text(
                      'Please login to view notifications.',
                      style: TextStyle(fontSize: 16, color: Colors.black87),
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
                        onPressed: () => Navigator.of(context).pop(),
                        child: Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                          child: Text('OK',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
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
