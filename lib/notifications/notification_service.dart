import 'dart:async';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  late WebSocketChannel _channel;
  StreamController<Map<String, dynamic>> _notificationController =
      StreamController.broadcast();
  
  bool _isConnected = false;

  void connect(String userId) {
    if (_isConnected) return;

    final apiBaseUrl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';
    final channel = IOWebSocketChannel.connect(
      'ws://${apiBaseUrl.replaceFirst('http://', '').replaceFirst('https://', '')}/ws/notifications/$userId',
    );

    _channel = channel;
    _isConnected = true;

    channel.stream.listen(
      (message) {
        final data = Map<String, dynamic>.from(message);
        _notificationController.add(data);
      },
      onError: (error) {
        print('WebSocket error: $error');
        _isConnected = false;
      },
      onDone: () {
        print('WebSocket connection closed');
        _isConnected = false;
      },
    );
  }

  void disconnect() {
    if (_isConnected) {
      _channel.sink.close();
      _isConnected = false;
    }
  }

  Stream<Map<String, dynamic>> get notifications => _notificationController.stream;

  void dispose() {
    _notificationController.close();
    disconnect();
  }
}
