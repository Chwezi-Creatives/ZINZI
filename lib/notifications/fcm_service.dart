//cspell:disable
import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_provider.dart';
import 'notification_model.dart';

// Import FlutterLocalNotifications package only for mobile platforms
// We'll conditionally use this based on platform detection
// This avoids the web build error with flutter_local_notifications
// ignore: uri_does_not_exist
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show
        AndroidFlutterLocalNotificationsPlugin,
        AndroidInitializationSettings,
        AndroidNotificationChannel,
        AndroidNotificationDetails,
        DarwinInitializationSettings,
        FlutterLocalNotificationsPlugin,
        Importance,
        InitializationSettings,
        NotificationDetails,
        Priority;

// Global navigator key for navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Top-level background message handler
@pragma('vm:entry-point') // Required for background handlers
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    print('Handling a background message: ${message.messageId}');
    // Background handlers don't have access to UI, so just log it
    // We'll handle showing notifications elsewhere
    print('Background message data: ${message.data}');
  } catch (e) {
    print('Error in firebaseMessagingBackgroundHandler: $e');
  }
}

class FCMService {
  // Initialize Firebase Messaging instance with null safety
  static FirebaseMessaging? _firebaseMessaging;
  
  // Getter for Firebase Messaging instance
  static FirebaseMessaging get firebaseMessaging {
    _firebaseMessaging ??= FirebaseMessaging.instance;
    return _firebaseMessaging!;
  }

  // Initialize FlutterLocalNotificationsPlugin (only for mobile)
  static final FlutterLocalNotificationsPlugin? _notifications =
      kIsWeb ? null : FlutterLocalNotificationsPlugin();

  // Default notification channel
  static const AndroidNotificationChannel _defaultChannel =
      AndroidNotificationChannel(
    'zinzi_channel',
    'Zinzi Notifications',
    description: 'Channel for Zinzi app notifications',
    importance: Importance.max,
    playSound: true,
    showBadge: true,
    enableLights: true,
    enableVibration: true,
  );

  /// Initializes FCM with platform-specific settings
  static Future<void> initialize() async {
    try {
      // Add a small delay to ensure Firebase is fully initialized
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Platform-specific setup
      if (kIsWeb) {
        await _initializeWeb();
      } else if (Platform.isAndroid) {
        await _initializeAndroid();
      } else if (Platform.isIOS) {
        await _initializeIOS();
      }
      // Only attempt token registration if user_id and user_type are present (i.e., after login/signup)
      final prefs = await SharedPreferences.getInstance();
      final userType = prefs.getString('user_type');
      String? userId;
      if (userType != null) {
        switch (userType) {
          case 'chef':
            userId = prefs.getString('chef_user_id') ??
                prefs.getInt('ChefID')?.toString();
            break;
          case 'producer':
            userId = prefs.getString('producer_id') ??
                prefs.getInt('ProducerID')?.toString();
            break;
          case 'transporter':
            userId = prefs.getString('transporter_id') ??
                prefs.getInt('TransporterID')?.toString();
            break;
          case 'user':
          default:
            userId = prefs.getString('user_id') ??
                prefs.getInt('user_id')?.toString();
            break;
        }
      }
      if (userType != null && userId != null && userId.isNotEmpty) {
        FirebaseMessaging.instance.onTokenRefresh.listen((String? token) {
          if (token != null) _registerToken(token);
        });
        final String? initial = await FirebaseMessaging.instance.getToken();
        if (initial != null) _registerToken(initial);
      } else {
        print(
            'FCM token registration skipped: user_id or user_type missing (should occur only before login/signup)');
      }
    } catch (e) {
      print('FCM initialization error: $e');
    }
  }

  /// Call this after login/signup to register the FCM token with the latest user info
  static Future<void> registerTokenWithUserInfo() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _registerToken(token);
      }
    } catch (e) {
      print('Error registering FCM token with user info: $e');
    }
  }

  // Web-specific initialization
  static Future<void> _initializeWeb() async {
    try {
      // Add a small delay to ensure Firebase is fully initialized
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Request permission for web notifications
      await firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      
      // Add a small delay after permission request
      await Future.delayed(const Duration(milliseconds: 200));

      // Set up foreground message handler
      FirebaseMessaging.onMessage.listen(_handleMessage);

      // Set up background message handler (when app was closed and opened via notification)
      FirebaseMessaging.instance.getInitialMessage().then((m) {
        if (m != null) _handleMessage(m);
      });

      // Handle when a notification opens the app
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
    } catch (e) {
      print('FCM Web init error: $e');
    }
  }

  // Android-specific initialization
  static Future<void> _initializeAndroid() async {
    try {
      // Request permissions
      await FirebaseMessaging.instance.requestPermission(
          alert: true, badge: true, sound: true, provisional: false);

      // Configure how foreground notifications appear
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
              alert: true, badge: true, sound: true);

      // Set up local notifications
      const AndroidInitializationSettings androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings init =
          InitializationSettings(android: androidInit);

      await _notifications?.initialize(init,
          onDidReceiveNotificationResponse: (details) =>
              _handleNotificationTap(details.payload));

      // Create notification channel
      await _notifications
          ?.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_defaultChannel);

      // Set up message handlers
      FirebaseMessaging.onMessage.listen(_showNotification);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
      FirebaseMessaging.instance.getInitialMessage().then((m) {
        if (m != null) _showNotification(m);
      });

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      print('FCM Android init error: $e');
    }
  }

  // iOS-specific initialization
  static Future<void> _initializeIOS() async {
    try {
      // Request permissions
      await FirebaseMessaging.instance.requestPermission(
          alert: true, badge: true, sound: true, provisional: false);

      // Configure how foreground notifications appear
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
              alert: true, badge: true, sound: true);

      // Set up local notifications
      final DarwinInitializationSettings iosInit = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true);

      final InitializationSettings init = InitializationSettings(iOS: iosInit);

      await _notifications?.initialize(init,
          onDidReceiveNotificationResponse: (details) =>
              _handleNotificationTap(details.payload));

      // Set up message handlers
      FirebaseMessaging.onMessage.listen(_showNotification);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
      FirebaseMessaging.instance.getInitialMessage().then((m) {
        if (m != null) _showNotification(m);
      });

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      print('FCM iOS init error: $e');
    }
  }

  // Display a notification on mobile platforms
  static Future<void> _showNotification(RemoteMessage message) async {
    try {
      if (kIsWeb || message.notification == null) {
        return; // Web platform or no notification data
      }

      // Check notification preferences
      final prefs = await SharedPreferences.getInstance();
      bool notificationsEnabled =
          prefs.getBool('notifications_enabled') ?? true;

      // Configure the notification channel based on user preferences
      final AndroidNotificationChannel channel = AndroidNotificationChannel(
        _defaultChannel.id,
        _defaultChannel.name,
        description: _defaultChannel.description,
        importance: notificationsEnabled ? Importance.max : Importance.low,
        playSound: notificationsEnabled,
        showBadge: true, // Always show badge
        enableLights: notificationsEnabled,
        enableVibration: notificationsEnabled,
      );

      // Create the channel if on Android
      if (Platform.isAndroid) {
        await _notifications
            ?.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      }

      // Show notification
      await _notifications?.show(
        message.hashCode,
        message.notification!.title,
        message.notification!.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: channel.importance,
            priority: Priority.high,
            showWhen: true,
            playSound: notificationsEnabled,
            enableLights: notificationsEnabled,
            enableVibration: notificationsEnabled,
            fullScreenIntent: true, // Show notification immediately
          ),
        ),
        payload: jsonEncode(message.data),
      );

      // Add to notification provider if context is available
      final context = navigatorKey.currentContext;
      if (context != null) {
        _addNotificationToProvider(context, message);
      }
    } catch (e) {
      print('Error showing notification: $e');
    }
  }

  // Handle incoming messages (for web and when app is open)
  static Future<void> _handleMessage(RemoteMessage message) async {
    try {
      // For web platform, we need to manually update the provider
      if (kIsWeb && navigatorKey.currentContext != null) {
        _addNotificationToProvider(navigatorKey.currentContext!, message);
      }

      // For mobile platforms when the app is in foreground,
      // show the notification and update the provider
      if (!kIsWeb) {
        await _showNotification(message);
      }
    } catch (e) {
      print('Error handling message: $e');
    }
  }

  // Helper method to add a notification to the provider
  static void _addNotificationToProvider(
      BuildContext context, RemoteMessage message) {
    try {
      final notificationProvider = Provider.of<NotificationProvider>(
        context,
        listen: false,
      );

      // Create a notification model
      final notification = NotificationModel(
        id: message.messageId ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        type: message.data['type'] ?? 'order_status_changed',
        message: message.notification?.body ??
            'Order status updated to ${message.data['order_status'] ?? "unknown"}',
        data: message.data,
        timestamp: DateTime.now(),
        isRead: false,
      );

      // Add the notification
      notificationProvider.addNotification(notification);

      // Refresh the dashboard
      notificationProvider.refreshDashboard();
    } catch (e) {
      print('Error adding notification to provider: $e');
    }
  }

  // Handle notification tap
  static Future<void> _handleNotificationTap(String? payload) async {
    if (payload == null) return;

    try {
      final data = jsonDecode(payload);
      final navigator = navigatorKey.currentState;
      if (navigator == null) return;

      // Navigate to appropriate screen based on notification type
      if (data['type'] == 'order_status_changed') {
        final orderId = data['order_id'];
        final status = data['status'];
        final userType = data['user_type'] ?? 'user';

        // Map user type to route
        final Map<String, String> routeMap = {
          'chef': '/chef_orders',
          'producer': '/producer_orders',
          'transporter': '/transporter_orders',
          'user': '/order_details',
        };

        // Get route or default to order details
        final route = routeMap[userType] ?? '/order_details';

        // Navigate
        navigator.pushNamed(route,
            arguments: {'order_id': orderId, 'status': status});
      }
    } catch (error) {
      print('Error handling notification tap: $error');
    }
  }

  // Register FCM token with backend
  static Future<void> _registerToken(String token) async {
    try {
      // Check if notifications are enabled
      final prefs = await SharedPreferences.getInstance();
      bool notificationsEnabled =
          prefs.getBool('notifications_enabled') ?? true;

      if (!notificationsEnabled) {
        print('Notifications are disabled by user preference');
        return;
      }

      // Get user type and ID from shared preferences (simplified approach)
      String? userType = prefs.getString('user_type') ?? 'user';
      String? userId;

      // Try to get user ID based on user type
      switch (userType) {
        case 'chef':
          userId = prefs.getString('chef_user_id') ??
              prefs.getInt('ChefID')?.toString();
          break;
        case 'producer':
          userId = prefs.getString('producer_id') ??
              prefs.getInt('ProducerID')?.toString();
          break;
        case 'transporter':
          userId = prefs.getString('transporter_id') ??
              prefs.getInt('TransporterID')?.toString();
          break;
        case 'user':
        default:
          userId =
              prefs.getString('user_id') ?? prefs.getInt('user_id')?.toString();
          break;
      }

      if (userId == null || userId.isEmpty) {
        print('User ID not available for token registration');
        return;
      }

      // Determine platform
      String platform;
      if (kIsWeb) {
        platform = 'web';
      } else if (Platform.isAndroid) {
        platform = 'android';
      } else if (Platform.isIOS) {
        platform = 'ios';
      } else {
        platform = 'unknown';
      }

      // Register token with backend
      final baseUrl = dotenv.env['API_BASE_URL'];
      if (baseUrl == null || baseUrl.isEmpty) {
        print('API_BASE_URL not found in environment variables');
        return;
      }

      final endpoint = '$baseUrl/rr/notifications/tokens';
      final payload = {
        'token': token,
        'platform': platform,
        'user_type': userType,
        'user_id': userId
      };
      print('[FCM] Registering token. Endpoint: ' +
          endpoint +
          ', Payload: ' +
          payload.toString());
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        print('Token registered successfully');
      } else {
        print(
            'Failed to register token: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error registering token: $e');
    }
  }

  // Get current FCM token
  static Future<String?> getFCMToken() async {
    try {
      return await firebaseMessaging.getToken();
    } catch (e) {
      print('Error getting FCM token: $e');
      return null;
    }
  }

  // Subscribe to a specific topic
  static Future<void> subscribeToTopic(String topic) async {
    try {
      await firebaseMessaging.subscribeToTopic(topic);
      print('Subscribed to topic: $topic');
    } catch (e) {
      print('Error subscribing to topic: $e');
    }
  }

  // Unsubscribe from a specific topic
  static Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await firebaseMessaging.unsubscribeFromTopic(topic);
      print('Unsubscribed from topic: $topic');
    } catch (e) {
      print('Error unsubscribing from topic: $e');
    }
  }

  // Toggle notification preferences
  static Future<void> toggleNotifications(bool enabled) async {
    try {
      // Save preference
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', enabled);

      // Skip channel updates on web platform
      if (kIsWeb) return;

      // Update Android notification channel based on preference
      final androidPlugin =
          _notifications?.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        // Create an appropriate channel based on preferences
        await androidPlugin.createNotificationChannel(
          AndroidNotificationChannel(
            _defaultChannel.id,
            _defaultChannel.name,
            description: _defaultChannel.description,
            importance: enabled ? Importance.max : Importance.low,
            playSound: enabled,
            showBadge: true, // Always show badge
            enableLights: enabled,
            enableVibration: enabled,
          ),
        );
      }
    } catch (e) {
      print('Error toggling notifications: $e');
    }
  }

  /// Deactivates the FCM token with the backend (call on logout or when disabling notifications)
  static Future<void> deactivateTokenWithBackend() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = await firebaseMessaging.getToken();
      if (token == null) {
        print('[FCM] No token available for deactivation');
        return;
      }

      // Get user type and ID from shared preferences (same logic as _registerToken)
      String? userType = prefs.getString('user_type') ?? 'user';
      String? userId;
      switch (userType) {
        case 'chef':
          userId = prefs.getString('chef_user_id') ??
              prefs.getInt('ChefID')?.toString();
          break;
        case 'producer':
          userId = prefs.getString('producer_id') ??
              prefs.getInt('ProducerID')?.toString();
          break;
        case 'transporter':
          userId = prefs.getString('transporter_id') ??
              prefs.getInt('TransporterID')?.toString();
          break;
        case 'user':
        default:
          userId =
              prefs.getString('user_id') ?? prefs.getInt('user_id')?.toString();
          break;
      }
      if (userId == null || userId.isEmpty) {
        print('[FCM] User ID not available for token deactivation');
        return;
      }

      final baseUrl = dotenv.env['API_BASE_URL'];
      if (baseUrl == null || baseUrl.isEmpty) {
        print('[FCM] API_BASE_URL not found in environment variables');
        return;
      }
      final endpoint = '$baseUrl/rr/notifications/tokens/deactivate';
      final payload = {
        'token': token,
        'user_type': userType,
        'user_id': userId,
      };
      print('[FCM] Deactivating token. Endpoint: ' +
          endpoint +
          ', Payload: ' +
          payload.toString());
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        print('[FCM] Token deactivated successfully');
      } else {
        print(
            '[FCM] Failed to deactivate token: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('[FCM] Error deactivating token: $e');
    }
  }
}
