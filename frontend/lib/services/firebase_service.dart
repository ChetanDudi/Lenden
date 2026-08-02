import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/api_client.dart';

// Must be a top-level function — runs in an isolate when app is terminated/background
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
  // FCM automatically shows the notification from the payload — nothing extra needed
}

class FirebaseService {
  static final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  static const _channelId   = 'lenden_high_importance';
  static const _channelName = 'LenDen Notifications';
  static const _channelDesc = 'Payment alerts and important updates from LenDen';

  static Future<void> initialize() async {
    if (kIsWeb) return;

    await Firebase.initializeApp();

    // Register the background/terminated handler
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

    // Local notifications (needed to show alerts while app is in foreground)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifs.initialize(const InitializationSettings(android: androidInit));

    // Create the high-importance notification channel (Android 8+)
    await _localNotifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
        ));

    // Request notification permission from the user
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground messages — FCM suppresses the system notification by default,
    // so we show it manually via flutter_local_notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      final n = msg.notification;
      if (n == null) return;
      _localNotifs.show(
        msg.hashCode,
        n.title,
        n.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        payload: jsonEncode(msg.data),
      );
    });

    // Listen for token refreshes and re-upload to backend automatically
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      ApiClient.post('/api/users/fcm-token', body: {'fcmToken': token})
          .catchError((_) {});
    });
  }

  /// Upload the current FCM token to our backend.
  /// Call this right after a successful login and on cold-start if already logged in.
  static Future<void> uploadToken() async {
    if (kIsWeb) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await ApiClient.post('/api/users/fcm-token', body: {'fcmToken': token});
    } catch (_) {}
  }

  /// Delete the FCM token on logout so the device stops receiving notifications.
  static Future<void> deleteToken() async {
    if (kIsWeb) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
