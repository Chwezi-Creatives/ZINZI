import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'notifications/notification_provider.dart';
import 'notifications/fcm_service.dart';
import 'notifications/notification_badge.dart';
import 'app_drawer_unified.dart';
import 'http_overrides.dart';
import 'splash.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print("Initializing WidgetsBinding");

  await dotenv.load(fileName: ".env");
  print(".env file loaded");

  final certBytes = await rootBundle.load('assets/images/selfsigned.crt');
  print("Certificate loaded");

  final cert = certBytes.buffer.asUint8List();
  HttpOverrides.global = MyHttpOverrides(cert);
  print("HTTP Overrides set");

  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: "AIzaSyAtPIxFkbzNtZ8_9ADNmb_6IriS_0jD4kE",
          authDomain: "zinzi-fcm2.firebaseapp.com",
          projectId: "zinzi-fcm2",
          storageBucket: "zinzi-fcm2.firebasestorage.app",
          messagingSenderId: "140229310127",
          appId: "1:140229310127:web:05f48494c489bd048b065a",
          measurementId: "G-HFLZEDCKZN",
        ),
      );
      print("Firebase initialized (web)");
    } else {
      await Firebase.initializeApp();
      print("Firebase initialized (mobile)");
    }

    // Request notification permissions for web and iOS
    if (kIsWeb) {
      await FCMService.initialize();
      print("FCMService initialized (web)");
    } else if (Platform.isIOS) {
      await FCMService.initialize();
      print("FCMService initialized (iOS)");
    } else {
      await FCMService.initialize();
      print("FCMService initialized (Android)");
    }
  } catch (e) {
    print("Error initializing Firebase/FCM: $e");
  }

  // Initialize drawer data
  try {
    await AppDrawer.initializeUserData();
    print("Drawer data initialized");
  } catch (e) {
    print("Error initializing drawer data: $e");
  }

  runApp(MyApp());
  print("App started");
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<NotificationProvider>(
      create: (_) => NotificationProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.teal,
        ),
        home: Stack(
          children: [
            SplashScreen(),
            const GlobalNotificationBadge(),
          ],
        ),
      ),
    );
  }
}
