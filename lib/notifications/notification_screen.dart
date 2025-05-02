import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zinzi2/notifications/notification_model.dart';
import 'notification_provider.dart';
import 'notification_widget.dart';
import 'websocket_service.dart';
import '../services/user_service.dart';
import 'notification_feedback_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert' as json;

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({Key? key}) : super(key: key);

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  late UserService _userService;
  late WebSocketService _webSocketService;
  late SharedPreferences _prefs;
  late NotificationFeedbackService _feedbackService;
  bool _isWebSocketConnected = false;
  String? _webSocketError;
  int? _userId;

  @override
  void initState() {
    super.initState();
    _userService = UserService();
    _loadUserId();
    _initFeedbackService();
    
    // Initialize the provider
    final provider = Provider.of<NotificationProvider>(context, listen: false);
    provider.initialize(''); // Initialize with empty string, will update later
    
    // Initialize WebSocket service
    _webSocketService = WebSocketService(provider);
  }

  Future<void> _initFeedbackService() async {
    _prefs = await SharedPreferences.getInstance();
    _feedbackService = NotificationFeedbackService(_prefs);
  }

  void _loadUserId() async {
    final userId = await _userService.getUserId();
    if (userId != null) {
      setState(() {
        _userId = userId;
      });
      
      // Initialize provider with correct user ID
      final provider = Provider.of<NotificationProvider>(context, listen: false);
      provider.initialize(_userId.toString());
      
      // Initialize feedback service
      await _initFeedbackService();
      
      // Connect WebSocket
      _connectWebSocket();
    }
  }

  void _connectWebSocket() async {
    if (_userId == null) {
      setState(() {
        _isWebSocketConnected = false;
        _webSocketError = 'No user ID available';
      });
      return;
    }

    try {
      setState(() {
        _isWebSocketConnected = false;
        _webSocketError = null;
      });
      
      await _webSocketService.connect();
      setState(() {
        _isWebSocketConnected = true;
        _webSocketError = null;
      });
    } catch (e) {
      setState(() {
        _isWebSocketConnected = false;
        _webSocketError = 'Failed to connect to WebSocket: ${e.toString()}';
      });
    }
  }

  void handleNotification(dynamic message) {
    try {
      if (message is! String) {
        print('Invalid notification message format: $message');
        return;
      }
      
      final notification = json.jsonDecode(message);
      if (notification is! Map<String, dynamic>) {
        print('Invalid notification data format: $notification');
        return;
      }
      
      final notificationModel = NotificationModel.fromJson(notification);
      final provider = Provider.of<NotificationProvider>(context, listen: false);
      provider.addNotification(notificationModel);
      
      // Give feedback for the notification
      _feedbackService.giveFeedback();
    } catch (e, stackTrace) {
      print('Error handling notification: $e\n$stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<NotificationProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              provider.clearNotifications();
            },
          ),
          IconButton(
            icon: Icon(
              _isWebSocketConnected ? Icons.wifi : Icons.wifi_off,
              color: _isWebSocketConnected ? Colors.green : Colors.red,
            ),
            onPressed: () {
              if (_isWebSocketConnected) {
                // Close the WebSocket connection
                _webSocketService.disconnect();
                setState(() {
                  _isWebSocketConnected = false;
                });
              } else {
                _connectWebSocket();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_webSocketError != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _webSocketError!,
                style: const TextStyle(
                  color: Colors.red,
                ),
              ),
            ),
          if (provider.hasError)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                provider.error ?? 'Unknown error',
                style: const TextStyle(
                  color: Colors.red,
                ),
              ),
            ),
          Expanded(
            child: provider.isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : provider.notifications.isEmpty
                    ? const Center(
                        child: Text('No notifications yet'),
                      )
                    : ListView.builder(
                        itemCount: provider.notifications.length,
                        itemBuilder: (context, index) {
                          final notification = provider.notifications[index];
                          return Dismissible(
                            key: Key(notification.id),
                            onDismissed: (direction) {
                              provider.markAsRead(notification.id);
                            },
                            child: NotificationWidget(
                              notification: notification,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
