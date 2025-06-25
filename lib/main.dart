// cspell:disable
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode, kDebugMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:zinzi/splash.dart';
import 'package:zinzi/user_preferences.dart';
import 'notifications/notification_provider.dart';
import 'notifications/fcm_service.dart'
    if (dart.library.js) 'notifications/fcm_service_web.dart' as fcm;
import 'notifications/notification_badge.dart';
import 'package:zinzi/app_drawer_unified.dart';
import 'package:zinzi/platform_info.dart';
import 'package:zinzi/services/performance_service.dart';
import 'package:zinzi/utils/route_observer.dart';

import 'package:device_preview/device_preview.dart';
import 'package:device_preview_screenshot/device_preview_screenshot.dart';

// Route observer instance
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

// Toggle this to true when you want Device Preview in debug/profile mode
const bool enableDevicePreview = false;

void main() async {
  // Start performance monitoring
  PerformanceService.startTimer();

  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize services
    await PerformanceService.initialize();
    await dotenv.load(fileName: ".env");
    await _initializeFirebase();
    await Future.delayed(const Duration(milliseconds: 500));
    await _initializeFCM().catchError((error) {
      print('FCM initialization failed: $error');
    });
    await _initializeDrawer().catchError((error) {
      print('Drawer initialization failed: $error');
    });

    // End performance monitoring
    PerformanceService.endTimer();

    final bool shouldEnableDevicePreview = !kReleaseMode && enableDevicePreview;

    runApp(
      DevicePreview(
        enabled: shouldEnableDevicePreview,
        tools: [
          ...DevicePreview.defaultTools,
          const DevicePreviewScreenshot(),
        ],
        builder: (context) => const MyApp(),
      ),
    );
  } catch (e) {
    print('Error during initialization: $e');

    final bool shouldEnableDevicePreview = !kReleaseMode && enableDevicePreview;

    runApp(
      DevicePreview(
        enabled: shouldEnableDevicePreview,
        tools: [
          ...DevicePreview.defaultTools,
          const DevicePreviewScreenshot(),
        ],
        builder: (context) => const MyApp(),
      ),
    );
  }
}

// Firebase initialization
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

// FCM initialization
Future<void> _initializeFCM() async {
  try {
    await Future.delayed(const Duration(milliseconds: 300));
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

    await Future.delayed(const Duration(milliseconds: 200));
  } catch (e) {
    print("Error initializing FCM: $e");
    rethrow;
  }
}

// Drawer initialization (currently a placeholder)
Future<void> _initializeDrawer() async {
  try {
    print("Drawer will initialize data when created");
  } catch (e) {
    print("Error initializing drawer data: $e");
  }
}

// Main App
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
          locale: DevicePreview.locale(context),
          builder: DevicePreview.appBuilder,
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
