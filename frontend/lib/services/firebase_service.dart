import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/api_client.dart';

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class FirebaseService {
  static Future<void> initialize() async {
    if (kIsWeb) return;

    await Firebase.initializeApp();

    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // FCM shows the notification automatically when app is background/killed.
    // onMessage fires when app is in foreground — no system banner needed here.
    FirebaseMessaging.onMessage.listen((_) {});

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      ApiClient.post('/api/users/fcm-token', body: {'fcmToken': token})
          .catchError((_) {});
    });
  }

  static Future<void> uploadToken() async {
    if (kIsWeb) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await ApiClient.post('/api/users/fcm-token', body: {'fcmToken': token});
    } catch (_) {}
  }

  static Future<void> deleteToken() async {
    if (kIsWeb) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
