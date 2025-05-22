//cspell:disable
// Web-specific implementation for FCM service
// This file provides a stub implementation for web platform

import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_provider.dart';
import 'notification_model.dart';

// Global navigator key for navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Top-level background message handler for web
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    print('Handling a background message in web: ${message.messageId}');
    print('Background message data: ${message.data}');
  } catch (e) {
    print('Error in web firebaseMessagingBackgroundHandler: $e');
  }
}

class FCMService {
  // We use FirebaseMessaging.instance directly instead of a static field

  /// Initializes FCM for web platform
  static Future<void> initialize() async {
    try {
      await _initializeWeb();

      // Only attempt token registration if user_id and user_type are present
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
      print('FCM web initialization error: $e');
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
      // Request permission for web notifications
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

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

  // Handle incoming messages (for web)
  static Future<void> _handleMessage(RemoteMessage message) async {
    try {
      // For web platform, we need to manually update the provider
      if (navigatorKey.currentContext != null) {
        _addNotificationToProvider(navigatorKey.currentContext!, message);
      }

      // Handle navigation based on notification type
      _handleNotificationTap(jsonEncode(message.data));
    } catch (e) {
      print('Error handling web message: $e');
    }
  }

  // Handle notification tap
  static Future<void> _handleNotificationTap(String? payload) async {
    if (payload == null) return;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final notificationType = data['type'] as String?;

      // Navigate based on notification type
      if (notificationType != null && navigatorKey.currentState != null) {
        // Handle navigation based on notification type
        // This will be implemented based on app-specific navigation requirements
      }
    } catch (e) {
      print('Error handling notification tap: $e');
    }
  }

  // Add notification to provider
  static void _addNotificationToProvider(
      BuildContext context, RemoteMessage message) {
    try {
      final provider =
          Provider.of<NotificationProvider>(context, listen: false);
      final notification = NotificationModel(
        id: message.messageId ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        type: message.data['type'] as String? ?? 'general',
        message: message.notification?.body ?? '',
        data: message.data,
        timestamp: DateTime.now(),
        isRead: false,
      );
      provider.addNotification(notification);
    } catch (e) {
      print('Error adding notification to provider: $e');
    }
  }

  // Register FCM token with backend
  static Future<void> _registerToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userType = prefs.getString('user_type');
      String? userId;

      // Get user ID based on user type
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

      if (userType == null || userId == null || userId.isEmpty) {
        print('Cannot register FCM token: missing user type or ID');
        return;
      }

      // Get API endpoint from .env
      final apiUrl = dotenv.env['API_URL'] ?? 'http://localhost:5000';
      final endpoint = '$apiUrl/rr/notifications/tokens';

      // Prepare request payload
      final payload = {
        'token': token,
        'platform': 'web',
        'user_type': userType,
        'user_id': userId,
      };

      print('[FCM] Registering token. Endpoint: $endpoint, Payload: $payload');

      // Send request to backend
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('Token registered successfully');
      } else {
        print(
            'Failed to register token: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Error registering FCM token: $e');
    }
  }
}
