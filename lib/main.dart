//cspell:disable
// Remove the old problematic import:
// import 'dart:io' if (dart.library.js) 'dart:html' as io; NO!

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:zinzi2/splash.dart';
import 'notifications/notification_provider.dart';
// Conditionally import the appropriate FCM service implementation
import 'notifications/fcm_service.dart'
    if (dart.library.js) 'notifications/fcm_service_web.dart' as fcm;
import 'notifications/notification_badge.dart';
import 'package:zinzi2/app_drawer_unified.dart';
import 'package:zinzi2/platform_info.dart'; // For OS check
import 'package:zinzi2/services/performance_service.dart';
import 'package:zinzi2/utils/route_observer.dart';

// Create a global route observer
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

void main() async {
  // Start performance monitoring
  PerformanceService.startTimer();

  WidgetsFlutterBinding.ensureInitialized();

  // Initialize performance service
  await PerformanceService.initialize();

  // Load environment variables in parallel with other initializations
  final envLoad = dotenv.load(fileName: ".env");

  // Initialize Firebase and FCM in parallel
  final firebaseInit = _initializeFirebase();
  final fcmInit = _initializeFCM();
  final drawerInit = _initializeDrawer();

  // Wait for all async operations to complete
  await Future.wait([
    envLoad,
    firebaseInit,
    fcmInit,
    drawerInit,
  ]);

  // End performance monitoring
  PerformanceService.endTimer();

  runApp(const MyApp());
}

// Initialize Firebase in the background
Future<void> _initializeFirebase() async {
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
      print("Firebase initialized (mobile/desktop)");
    }
  } catch (e) {
    print("Error initializing Firebase: $e");
  }
}

// Initialize FCM in the background
Future<void> _initializeFCM() async {
  try {
    await fcm.FCMService.initialize();
    if (kIsWeb) {
      print("FCMService initialized (web)");
    } else {
      final os = getOperatingSystem();
      if (isIOS()) {
        print("FCMService initialized (iOS)");
      } else if (isAndroid()) {
        print("FCMService initialized (Android)");
      } else {
        print("FCMService initialized (other non-web OS: $os)");
      }
    }
  } catch (e) {
    print("Error initializing FCM: $e");
  }
}

// Initialize drawer data in the background
Future<void> _initializeDrawer() async {
  try {
    await AppDrawer.initializeUserData();
    print("Drawer data initialized");
  } catch (e) {
    print("Error initializing drawer data: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<NotificationProvider>(
      create: (_) => NotificationProvider(),
      child: RouteObserverProvider(
        routeObserver: routeObserver,
        child: MaterialApp(
          navigatorObservers: [routeObserver],
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
      ),
    );
  }
}
