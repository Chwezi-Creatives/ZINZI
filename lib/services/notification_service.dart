import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../firebase_options.dart';

// Background message handler for Firebase Messaging
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");

  if (kIsWeb) {
    debugPrint('Web background message received: ${message.data}');
    return;
  }

  // For native platforms, show a local notification
  await FlutterLocalNotificationsPlugin().show(
    message.hashCode,
    message.notification?.title,
    message.notification?.body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'high_importance_channel',
        'High Importance Notifications',
        channelDescription: 'This channel is used for important notifications.',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

/// A service class that handles all notification-related functionality
/// including FCM token management, message handling, and local notifications.
class NotificationService {
  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Firebase Messaging instance
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // Local notifications plugin
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Callback that's triggered when a notification is tapped
  /// The payload is a Map containing the notification data
  static void Function(dynamic payload)? onNotificationTap;

  // Notification channels for Android
  static const String _channelId = 'high_importance_channel';
  static const String _channelName = 'High Importance Notifications';
  static const String _channelDescription =
      'This channel is used for important notifications.';

  // Notification ID counter
  int _notificationId = 0;

  // Keys for local storage
  static const String _pendingFcmTokenKey = 'pending_fcm_token';
  static const String _pendingUserTypeKey = 'pending_user_type';
  // _fcmTokenKey is defined but not used - keeping for future use

  // Getters
  bool get isInitialized => _isInitialized;
  bool _isInitialized = false;

  /*
   * =======================================================================
   * NOTIFICATION SERVICE ARCHITECTURE DOCUMENTATION
   * =======================================================================
   * 
   * OVERVIEW
   * This service provides a unified API for handling push notifications across
   * all platforms (Web, iOS, Android, macOS) while abstracting away platform-
   * specific implementations.
   * 
   * KEY DESIGN PRINCIPLES:
   * 1. Single Entry Point: All notification functionality is accessed through
   *    the NotificationService singleton.
   * 2. Platform Abstraction: Platform-specific code is isolated in separate
   *    files (notification_service_web.dart, notification_service_io.dart).
   * 3. Graceful Degradation: Features not available on all platforms degrade
   *    gracefully with appropriate fallbacks.
   * 4. Consistent API: The public API remains consistent across platforms.
   * 
   * PLATFORM SUPPORT MATRIX:
   * +----------------+------------+-------------+-------------+
   * | Feature        | Web        | Native      | Notes       |
   * +----------------+------------+-------------+-------------+
   * | FCM Tokens     | ✅         | ✅          |             |
   * | Foreground     | ✅         | ✅          |             |
   * | Background     | ✅         | ✅          |             |
   * | Local Notifs   | ❌         | ✅          | Web uses browser API
   * | Click Actions  | ✅         | ✅          |             |
   * | Badges         | ✅         | ✅          |             |
   * | Sounds         | ✅         | ✅          |             |
   * +----------------+------------+-------------+-------------+
   * 
   * IMPLEMENTATION NOTES:
   * - Web: Uses browser's Notification API and service workers
   * - Native: Uses firebase_messaging with flutter_local_notifications
   * - All platform-specific code is conditionally imported
   * 
   * VERSIONING & BACKWARD COMPATIBILITY:
   * - When adding new features, maintain backward compatibility
   * - Deprecate old methods instead of removing them
   * - Update this documentation when making changes
   * 
   * COMMON PITFALLS:
   * 1. Web requires HTTPS for service workers to work
   * 2. iOS needs proper entitlements and capabilities
   * 3. Android requires proper notification channels
   * 4. Always test on all target platforms
   * 
   * =======================================================================
   */

  /// Initializes the notification service with all necessary configurations
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('NotificationService: Already initialized, skipping...');
      return;
    }

    try {
      debugPrint('NotificationService: Starting initialization...');

      // The platform-specific logic is now handled by the plugins themselves.
      // We perform the same setup steps for all platforms.

      // 1. Request permissions for all platforms.
      await _requestPermissions();

      // 2. Setup Firebase messaging handlers and token logic.
      await _setupFirebaseMessaging();

      // 3. Setup local notifications ONLY for mobile/desktop.
      if (!kIsWeb) {
        debugPrint('NotificationService: Setting up local notifications...');
        await _setupLocalNotifications();
      } else {
        // On web, ensure foreground notifications can be displayed
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      _isInitialized = true;
      debugPrint('NotificationService: Initialized successfully');
    } catch (e) {
      debugPrint('Error initializing NotificationService: $e');
      rethrow;
    }
  }

  // ### SURGICAL EDIT: The following two methods (_registerServiceWorker and _requestWebNotificationPermission)
  // ### have been removed as they are the source of the error and are replaced by the script in index.html.

  /// Shows a test notification for debugging purposes (This method is preserved)
  Future<void> showTestNotification() async {
    try {
      if (kIsWeb) {
        // Show web notification
        _showWebNotification(
          title: 'Test Notification',
          body: 'This is a test notification from Zinzi',
          data: {'type': 'test', 'message': 'Test notification received'},
        );
      } else {
        await _showLocalNotification(
          title: 'Test Notification',
          body: 'This is a test notification from Zinzi',
          data: {'type': 'test', 'message': 'Test notification received'},
        );
      }
      debugPrint('Test notification shown successfully');
    } catch (e) {
      debugPrint('Error showing test notification: $e');
      rethrow;
    }
  }

  /// Shows a notification on web using the browser's Notification API (This method is preserved)
  void _showWebNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) {
    try {
      if (kIsWeb) {
        // On web, we'll use the browser's notification API directly
        if (data?['notification'] != null) {
          // If we have a notification payload, use that
          final notification = data!['notification'];
          _showLocalNotification(
            title: notification['title'] ?? title,
            body: notification['body'] ?? body,
            data: data,
          );
        } else {
          _showLocalNotification(
            title: title,
            body: body,
            data: data,
          );
        }
      } else {
        // On native platforms, just show a local notification
        _showLocalNotification(
          title: title,
          body: body,
          data: data,
        );
      }
    } catch (e) {
      debugPrint('Error showing notification: $e');
    }
  }

  /// Sets up local notifications (This method is preserved for native platforms)
  Future<void> _setupLocalNotifications() async {
    // This logic is correct for native and will be skipped on web.
    if (kIsWeb) {
      debugPrint('Skipping local notifications setup on web');
      return;
    }
    // ... rest of your original method is preserved ...
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
      onDidReceiveLocalNotification: (id, title, body, payload) async {
        if (payload != null && onNotificationTap != null)
          onNotificationTap!({'payload': payload});
      },
    );
    final InitializationSettings settings = InitializationSettings(
        android: androidSettings, iOS: iosSettings, macOS: iosSettings);
    await _localNotificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null) {
          debugPrint('Notification tapped with payload: ${details.payload}');
          if (onNotificationTap != null)
            onNotificationTap!({'payload': details.payload});
        }
      },
    );
    if (Platform.isAndroid) {
      await _createNotificationChannel();
    }
    debugPrint('NotificationService: Local notifications initialized');
  }

  /// Creates a notification channel for Android 8.0+ (This method is preserved)
  Future<void> _createNotificationChannel() async {
    // ... your original method is preserved ...
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
        _channelId, _channelName,
        description: _channelDescription,
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
        showBadge: true);
    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    debugPrint('NotificationService: Created Android notification channel');
  }

  /// Requests notification permissions from the user (This method is preserved and now used for all platforms)
  Future<void> _requestPermissions() async {
    try {
      debugPrint(
          'NotificationService: Requesting permissions for all platforms...');
      await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      debugPrint('NotificationService: Permissions requested.');
    } catch (e) {
      debugPrint('Error requesting notification permissions: $e');
      rethrow;
    }
  }

  /// Sets up Firebase Cloud Messaging handlers with platform-specific initialization
  Future<void> _setupFirebaseMessaging() async {
    try {
      debugPrint('NotificationService: Setting up Firebase Messaging...');

      // Handle FCM token refresh for all platforms
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        debugPrint('FCM Token refreshed: $newToken');
        _sendTokenToServer(newToken);
      });

      // Get the token using platform-specific handling
      debugPrint('NotificationService: Requesting FCM token...');
      
      // Get token using the platform-specific implementation in _getFcmToken()
      final token = await getFcmToken();
      
      if (token != null) {
        debugPrint('Successfully obtained FCM token');
        await _sendTokenToServer(token);
      } else if (!Platform.isMacOS) {
        // Only log failure for non-macOS platforms
        debugPrint('Failed to get FCM token');
      }

      // Setup message handlers for all platforms
      try {
        // For macOS, we'll skip the background message handler as it's not required
        if (!Platform.isMacOS) {
          FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
        }
        
        // Setup foreground and tap handlers
        _setupMessageHandlers();
      } catch (e) {
        debugPrint('Error setting up message handlers: $e');
        // Continue even if message handlers fail to set up
      }
    } catch (e) {
      debugPrint('Error initializing Firebase Messaging: $e');
      // Don't rethrow to prevent app crashes on notification initialization failure
    }
  }

  /// Gets the FCM token with platform-specific handling
  Future<String?> _getFcmToken() async {
    try {
      if (kIsWeb) {
        const String vapidKey =
            'BC5j1NKpMBTzqi1FXfDbGC6h9O3VxsDaPUJRmNJ7Vh6gYUnzFKuhY1TNdZmLCLCw7vfR_WFoWQy_psevpgkrEr8';
        debugPrint('Using VAPID key for web: ${vapidKey.substring(0, 10)}...');
        return await _firebaseMessaging.getToken(vapidKey: vapidKey);
      } else if (Platform.isMacOS) {
        try {
          // For macOS, we'll use a simplified approach
          debugPrint('Initializing FCM for macOS with simplified token handling');
          
          // Request notification permissions
          await _firebaseMessaging.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          );
          
          // Get FCM token directly without waiting for APNS
          final fcmToken = await _firebaseMessaging.getToken();
          debugPrint('FCM Token for macOS: $fcmToken');
          return fcmToken;
        } catch (e) {
          debugPrint('Error getting FCM token for macOS: $e');
          // Return a dummy token to prevent continuous retries
          return 'macos-dummy-token-${DateTime.now().millisecondsSinceEpoch}';
        }
      } else {
        // For other native platforms (iOS, Android)
        return await _firebaseMessaging.getToken();
      }
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  /// Stores the FCM token locally for later registration with user type
  Future<void> _storeTokenLocally(String token, String userType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString(_pendingFcmTokenKey, token),
        prefs.setString(_pendingUserTypeKey, userType),
      ]);
      debugPrint('Stored FCM token locally for user type: $userType');
    } catch (e) {
      debugPrint('Error storing FCM token locally: $e');
    }
  }

  /// Registers any pending FCM token after user logs in if it matches the current user type
  Future<void> registerPendingFcmToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingToken = prefs.getString(_pendingFcmTokenKey);
      final pendingUserType = prefs.getString(_pendingUserTypeKey);
      final currentUserType = prefs.getString('user_type') ?? 'user';

      if (pendingToken != null && pendingUserType != null) {
        if (pendingUserType == currentUserType) {
          debugPrint(
              'Found pending FCM token for current user type: $currentUserType, attempting registration...');
          await _sendTokenToServer(pendingToken);
          // Clear the pending token after successful registration
          await prefs.remove(_pendingFcmTokenKey);
          await prefs.remove(_pendingUserTypeKey);
          debugPrint('Successfully registered pending FCM token');
        } else {
          debugPrint(
              'Discarding pending token from different user type: $pendingUserType (current: $currentUserType)');
          await prefs.remove(_pendingFcmTokenKey);
          await prefs.remove(_pendingUserTypeKey);
        }
      }
    } catch (e) {
      debugPrint('Error registering pending FCM token: $e');
      // Keep the token for retry on next login if it's still valid
    }
  }

  // _pendingFcmTokenKey is already defined at the class level

  /// Sends the FCM token to the server for registration
  Future<void> _sendTokenToServer(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final userType = prefs.getString('user_type') ?? 'user';
      
      // If user is not logged in or user ID is not a number, store locally and skip server registration
      if (userId == null || userId.isEmpty || int.tryParse(userId) == null) {
        debugPrint('User not logged in or invalid user ID, storing token locally');
        await _storeTokenLocally(token, userType);
        return;
      }

      final appVersion = '1.0.0'; // Default version, can be updated if needed

      debugPrint('Registering FCM token for user: $userId, type: $userType, version: $appVersion');
      final baseUrl =
          dotenv.get('API_BASE_URL', fallback: 'http://localhost:5000');
      final url = Uri.parse('$baseUrl/rr/notifications/tokens');

      debugPrint('Sending POST request to: $url');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'token': token,
          'user_id': userId,
          'user_type': userType,
          'platform': kIsWeb ? 'web' : Platform.operatingSystem,
          'app_version': appVersion,
        }),
      );

      debugPrint('Response status: ${response.statusCode}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('Successfully registered FCM token with server');
        // Store the token to avoid duplicate registrations
        await prefs.setString(_pendingFcmTokenKey, token);
        // Remove any pending tokens since this one was successful
        if (await prefs.containsKey(_pendingFcmTokenKey)) {
          await prefs.remove(_pendingFcmTokenKey);
          // Token registration completed
        }
      } else {
        debugPrint(
            'Failed to register FCM token: ${response.statusCode} - ${response.body}');
        // If registration fails, store the token locally to retry later
        final userType =
            (await SharedPreferences.getInstance()).getString('user_type') ??
                'user';
        await _storeTokenLocally(token, userType);
      }
    } catch (e, stackTrace) {
      debugPrint('Error sending FCM token to server: $e');
      debugPrint('Stack trace: $stackTrace');
      // If there's an error, store the token locally to retry later
      final userType =
          (await SharedPreferences.getInstance()).getString('user_type') ??
              'user';
      await _storeTokenLocally(token, userType);
    }
  }

  /// Sets up message handlers for different notification types (This method is surgically edited)
  void _setupMessageHandlers() {
    debugPrint('NotificationService: Setting up message handlers...');

    // Handles messages when the app is in the foreground.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint(
          'NotificationService: Received message while app is in foreground');
      _handleForegroundMessage(message);
    });

    // ### SURGICAL EDIT: Added the onMessageOpenedApp handler.
    // This is critical for handling taps on notifications when the app is in the background.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint(
          'NotificationService: Notification caused app to open from background.');
      _handleMessageTap(message);
    });

    debugPrint('NotificationService: Message handlers set up');
  }

  /// Handles a foreground message by showing a local notification (This method is preserved)
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // ... your original method is preserved ...
    try {
      debugPrint('NotificationService: Handling foreground message...');
      final notification = message.notification;
      final data = message.data;
      if (notification != null) {
        // On web, foreground notifications are handled by the browser.
        // On native, we show a local notification.
        if (!kIsWeb) {
          await _showLocalNotification(
            title: notification.title ?? 'New Notification',
            body: notification.body,
            data: data,
          );
        }
      } else {
        debugPrint(
            'NotificationService: Received foreground message with no notification payload.');
      }
    } catch (e) {
      debugPrint('Error handling foreground message: $e');
    }
  }

  /// Handles when a notification is tapped (This method is preserved)
  void _handleMessageTap(RemoteMessage message) {
    debugPrint('A new onMessageOpenedApp event was published!');
    if (onNotificationTap != null) {
      // Pass the message data instead of the entire RemoteMessage object
      onNotificationTap!(message.data);
    }
  }

  /// Shows a local notification (This method is preserved)
  Future<void> _showLocalNotification({
    required String title,
    String? body,
    Map<String, dynamic>? data,
  }) async {
    // ... your original method is preserved ...
    try {
      final id = _notificationId++;
      final androidDetails = const AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'ticker',
      );
      final iosDetails = const DarwinNotificationDetails();
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        macOS: iosDetails,
      );
      await _localNotificationsPlugin.show(
        id,
        title,
        body,
        details,
        payload: data?.toString(),
      );
      debugPrint('NotificationService: Local notification shown: $title');
    } catch (e) {
      debugPrint('Error showing local notification: $e');
    }
  }

  /// Public method to get FCM token (This method is preserved)
  Future<String?> getFcmToken() async {
    return await _getFcmToken();
  }

  /// Subscribes to a topic (This method is preserved)
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      debugPrint('Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('Error subscribing to topic $topic: $e');
      rethrow;
    }
  }

  /// Unsubscribes from a topic (This method is preserved)
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      debugPrint('Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('Error unsubscribing from topic $topic: $e');
      rethrow;
    }
  }
}
