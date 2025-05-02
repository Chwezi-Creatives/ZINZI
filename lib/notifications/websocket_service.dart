import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'notification_provider.dart';
import 'notification_model.dart';

class WebSocketService {
  late WebSocketChannel _channel;
  final NotificationProvider _notificationProvider;
  final int _maxRetries = 5;
  int _retryCount = 0;
  bool _isConnecting = false;
  bool _isConnected = false;

  WebSocketService(this._notificationProvider);

  Future<void> connect() async {
    if (_isConnecting) return;
    _isConnecting = true;
    _retryCount = 0;

    try {
      // Get user ID from provider
      final userId = _notificationProvider.userId;
      if (userId == null) {
        _notificationProvider.showError('Cannot connect: User ID is not available');
        _isConnecting = false;
        return;
      }

      // Use the correct backend URL from the project structure
      final url = 'ws://localhost:8000/ws/$userId';
      print('Connecting to WebSocket: $url');
      
      _channel = WebSocketChannel.connect(Uri.parse(url));
      
      // Listen for messages
      _channel.stream.listen(
        (message) => handleNotification(message),
        onError: (error) => _handleConnectionError(int.tryParse(userId ?? '0')),
        onDone: () {
          print('WebSocket connection closed');
          _isConnected = false;
          _handleConnectionError(int.tryParse(userId ?? '0'));
        },
      );
      
      _isConnected = true;
      _retryCount = 0;
      _isConnecting = false;
      _notificationProvider.setConnected(true);
    } catch (e) {
      print('Failed to connect WebSocket: $e');
      _isConnecting = false;
      _isConnected = false;
      _handleConnectionError(null);
      rethrow;
    }
  }

  void _handleConnectionError(int? userId) {
    if (_retryCount < _maxRetries) {
      _retryCount++;
      final delay = Duration(seconds: 5 * _retryCount);
      print('Attempting to reconnect in ${delay.inSeconds} seconds...');
      Future.delayed(delay, () {
        connect();
      });
    } else {
      print('Max retries reached. Please check your connection.');
      _notificationProvider.showError('Failed to connect to notifications');
      _retryCount = 0;
      _isConnecting = false;
      _isConnected = false;
    }
  }

  void handleNotification(dynamic message) {
    try {
      if (message is! String) {
        print('Invalid notification message format: $message');
        return;
      }
      
      final notification = json.decode(message);
      if (notification is! Map<String, dynamic>) {
        print('Invalid notification data format: $notification');
        return;
      }
      
      final notificationModel = NotificationModel.fromJson(notification);
      _notificationProvider.addNotification(notificationModel);
    } catch (e, stackTrace) {
      print('Error handling notification: $e\n$stackTrace');
    }
  }

  void disconnect() {
    if (_isConnected) {
      _isConnected = false;
      _isConnecting = false;
      _retryCount = 0;
      try {
        _channel.sink.close();
      } catch (e) {
        print('Error closing WebSocket: $e');
      }
      _notificationProvider.setConnected(false);
    }
  }

  void dispose() {
    if (_isConnected) {
      disconnect();
    }
  }

  WebSocketChannel get channel => _channel;
  bool get isConnected => _isConnected;
}