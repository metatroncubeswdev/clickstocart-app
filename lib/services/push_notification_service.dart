import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Wraps Firebase Cloud Messaging end to end. Every step is try/catch
/// guarded so the app behaves exactly as before if `google-services.json` /
/// `GoogleService-Info.plist` aren't in place yet — push notifications just
/// stay inactive until those are added, nothing else breaks.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Call once, after the very first page has loaded — not at cold start,
  /// so the OS permission prompt doesn't hit people before they've seen the
  /// app do anything. [onNotificationTap] receives the in-app path to open
  /// (from the notification's `data.path` field) when a notification is
  /// tapped, whether the app was foregrounded, backgrounded, or terminated.
  Future<void> initialize({required void Function(String path) onNotificationTap}) async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint("Firebase not configured yet — push notifications stay off: $e");
      return;
    }

    try {
      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (response) {
          final path = response.payload;
          if (path != null && path.isNotEmpty) onNotificationTap(path);
        },
      );

      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint("Push permission: ${settings.authorizationStatus}");

      final token = await FirebaseMessaging.instance.getToken();
      debugPrint("FCM token: $token");
      // Once the Odoo-side registration endpoint exists (CLAUDE.md Phase 4 —
      // /mobile/register_push_token), send `token` there keyed to the
      // logged-in user so the backend can target this device.

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        debugPrint("FCM token refreshed: $newToken");
      });

      // Foreground: FCM doesn't show a system notification on its own, so
      // this shows one via flutter_local_notifications.
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);

      // Tapped while backgrounded.
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final path = message.data['path'];
        if (path != null) onNotificationTap(path);
      });

      // Tapped from a fully terminated state (app cold-started by the tap).
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        final path = initialMessage.data['path'];
        if (path != null) onNotificationTap(path);
      }
    } catch (e) {
      debugPrint("Push notification setup failed: $e");
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'default_channel',
      'General',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: details,
      payload: message.data['path'],
    );
  }
}

/// Must be a top-level function, registered before `runApp()` in main.dart —
/// handles a notification arriving while the app is backgrounded or killed.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  debugPrint("Background push received: ${message.messageId}");
}
