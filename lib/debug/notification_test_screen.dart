import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:universal_platform/universal_platform.dart';

class NotificationTestScreen extends StatefulWidget {
  const NotificationTestScreen({super.key});

  @override
  State<NotificationTestScreen> createState() => _NotificationTestScreenState();
}

class _NotificationTestScreenState extends State<NotificationTestScreen> {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  String _fcmToken = 'Fetching...';
  String _deviceInfo = 'Fetching...';
  String _lastNotification = 'No notifications received yet';
  bool _isLoading = true;
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _getDeviceInfo();
  }

  Future<void> _initNotifications() async {
    try {
      // Initialize local notifications
      await _localNotificationsPlugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
        ),
      );

      // Request notification permissions
      final settings = await _fcm.requestPermission();
      setState(() {
        _permissionsGranted = settings.authorizationStatus == AuthorizationStatus.authorized ||
                            settings.authorizationStatus == AuthorizationStatus.provisional;
      });

      // Get FCM token
      _fcm.getToken().then((token) {
        if (token != null) setState(() => _fcmToken = token);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle background/terminated app
      FirebaseMessaging.instance.getInitialMessage().then(_handleNotification);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotification);
    } catch (e) {
      setState(() => _lastNotification = 'Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _getDeviceInfo() async {
    String deviceInfoStr = '';
    
    try {
      if (UniversalPlatform.isAndroid) {
        deviceInfoStr = 'Android';
      } else if (UniversalPlatform.isIOS) {
        deviceInfoStr = 'iOS';
      } else if (UniversalPlatform.isMacOS) {
        deviceInfoStr = 'macOS';
      } else if (UniversalPlatform.isWindows) {
        deviceInfoStr = 'Windows';
      } else if (UniversalPlatform.isWeb) {
        deviceInfoStr = 'Web';
      } else {
        deviceInfoStr = 'Unknown Platform';
      }
      setState(() => _deviceInfo = deviceInfoStr);
    } catch (e) {
      setState(() => _deviceInfo = 'Error: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    _showLocalNotification(
      message.notification?.title ?? 'New Notification',
      message.notification?.body ?? '',
    );
    _updateLastNotification(message);
  }

  void _handleNotification(RemoteMessage? message) {
    if (message != null) _updateLastNotification(message);
  }

  void _updateLastNotification(RemoteMessage message) {
    setState(() {
      _lastNotification = '''
      Title: ${message.notification?.title ?? 'No title'}
      Body: ${message.notification?.body ?? 'No body'}
      Data: ${message.data}
      ''';
    });
  }

  Future<void> _showLocalNotification(String title, String body) async {
    final androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'Important notifications',
      importance: Importance.max,
    );
    
    final platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
    );
    
    await _localNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      platformDetails,
    );
  }

  Future<void> _sendTestNotification() async {
    try {
      await _showLocalNotification(
        'Test Notification',
        'This is a test notification at ${DateTime.now().toLocal()}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Tester')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildInfoCard(),
                  const SizedBox(height: 16),
                  _buildActionsCard(),
                  const SizedBox(height: 16),
                  _buildLastNotificationCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Device Info', style: TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            Text('Platform: ${UniversalPlatform.operatingSystem}'),
            Text('Device: $_deviceInfo'),
            const SizedBox(height: 8),
            const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            Text('Permissions: ${_permissionsGranted ? 'Granted' : 'Not Granted'}'),
            SelectableText('FCM Token: $_fcmToken'),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Actions', style: TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            ElevatedButton(
              onPressed: _permissionsGranted ? _sendTestNotification : null,
              child: const Text('Send Test Notification'),
            ),
            if (!_permissionsGranted)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Enable notifications in device settings',
                  style: TextStyle(color: Colors.orange),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastNotificationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Last Notification', style: TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            SelectableText(
              _lastNotification,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}
