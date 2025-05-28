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

  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize performance service
    await PerformanceService.initialize();

    // Load environment variables
    await dotenv.load(fileName: ".env");

    // Initialize Firebase first
    await _initializeFirebase();
    
    // Add a small delay to ensure Firebase is fully initialized
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Initialize FCM with error handling
    await _initializeFCM().catchError((error) {
      print('FCM initialization failed: $error');
      // Continue app startup even if FCM fails
    });

    // Initialize drawer data
    await _initializeDrawer().catchError((error) {
      print('Drawer initialization failed: $error');
      // Continue app startup even if drawer init fails
    });

    // End performance monitoring
    PerformanceService.endTimer();

    // Run the app
    runApp(const MyApp());
  } catch (e) {
    print('Error during initialization: $e');
    // Even if there's an error, we should still try to run the app
    runApp(const MyApp());
  }
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

// Initialize FCM in the background with proper error handling
Future<void> _initializeFCM() async {
  try {
    // Add a small delay to ensure Firebase is fully initialized
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Initialize FCM service
    await fcm.FCMService.initialize();
    
    if (kIsWeb) {
      print("FCMService initialized (web)");
    } else {
      try {
        final os = getOperatingSystem();
        if (isIOS()) {
          print("FCMService initialized (iOS)");
        } else if (isAndroid()) {
          print("FCMService initialized (Android)");
        } else {
          print("FCMService initialized (other non-web OS: $os)");
        }
      } catch (e) {
        print("Error getting OS info: $e");
      }
    }
    
    // Add a small delay to ensure FCM is fully initialized
    await Future.delayed(const Duration(milliseconds: 200));
  } catch (e) {
    print("Error initializing FCM: $e");
    rethrow; // Re-throw to be caught by the main try-catch
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
