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
    // Only initialize Firebase for mobile platforms
    if (!kIsWeb) {
      await Firebase.initializeApp();
      print("Firebase initialized");
      
      // Initialize Firebase Messaging only for mobile
      await FCMService.initialize();
      print("Firebase Messaging initialized");
    } else {
      print("Skipping Firebase initialization for web");
    }
  } catch (e) {
    print("Error initializing Firebase: $e");
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
