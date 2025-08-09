// cspell:disable
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'package:zinzi/splash.dart';
import 'notifications_UIs/notification_provider.dart';
import 'notifications_UIs/notification_badge.dart';
import 'package:zinzi/features/subscription/subscription_provider.dart';
import 'package:zinzi/services/performance_service.dart';
import 'package:zinzi/services/notification_service.dart';
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
    
    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // Initialize Notification Service with error handling
    try {
      final notificationService = NotificationService();
      await notificationService.initialize();
      
      // Set up notification tap handler
      NotificationService.onNotificationTap = (dynamic payload) {
        debugPrint('Notification tapped with payload: $payload');
        
        // Handle the payload based on its type
        if (payload is Map<String, dynamic>) {
          // Handle map payload (from data messages or notification data)
          debugPrint('Notification data: $payload');
          // Example: 
          // if (payload['type'] == 'message') {
          //   Navigator.pushNamed(context, '/messages', arguments: payload);
          // }
        } else if (payload is RemoteMessage) {
          // Handle RemoteMessage directly if needed
          debugPrint('RemoteMessage received: ${payload.messageId}');
          debugPrint('Notification data: ${payload.data}');
        }
      };
      
      // Get and log the FCM token
      final fcmToken = await notificationService.getFcmToken();
      if (fcmToken != null) {
        debugPrint('FCM Token: $fcmToken');
      }
    } catch (e) {
      debugPrint('Error initializing notification service: $e');
      // Re-throw if this is a critical error that should prevent app startup
      if (kDebugMode) rethrow;
    }
    
    // Initialize other services
    await Future.delayed(const Duration(milliseconds: 500));
    await _initializeDrawer().catchError((error) {
      debugPrint('Drawer initialization failed: $error');
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
    debugPrint('Error during initialization: $e');

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

// Firebase initialization is now handled directly in main()

// Drawer initialization (currently a placeholder)
Future<void> _initializeDrawer() async {
  try {
    debugPrint("Drawer will initialize data when created");
  } catch (e) {
    debugPrint("Error initializing drawer data: $e");
  }
}

// Main App
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
      ],
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
