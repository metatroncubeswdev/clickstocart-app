import 'package:clicks_to_cart/webview/webview_screen.dart';
import 'package:clicks_to_cart/services/push_notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Guarded: no-ops cleanly until google-services.json /
  // GoogleService-Info.plist are added — see push_notification_service.dart.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint("Firebase not configured yet: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClicksToCart',
     debugShowCheckedModeBanner: false,
      home: WebViewWithNav(),
    );
  }
}
