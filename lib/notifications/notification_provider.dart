import 'package:flutter/material.dart';
import 'notification_model.dart';
import 'dart:convert';

class NotificationProvider extends ChangeNotifier {
  List<NotificationModel> _notifications = [];
  bool _isLoading = false;
  bool _hasError = false;
  String? _error;
  String? _userId;
  bool _notificationsEnabled = true;
  bool _isConnected = false;

  NotificationProvider();

  List<NotificationModel> get notifications => _notifications;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String? get error => _error;
  bool get isConnected => _isConnected;
  String? get userId => _userId;

  void initialize(String userId) {
    _userId = userId;
    _hasError = false;
    _error = null;
    _isConnected = false;
    notifyListeners();
  }

  void addNotification(dynamic message) {
    if (!_notificationsEnabled) return;
    
    try {
      NotificationModel notification;
      if (message is String) {
        // Parse from JSON string
        final Map<String, dynamic> data = json.decode(message);
        notification = NotificationModel.fromJson(data);
      } else if (message is Map<String, dynamic>) {
        // Already a map
        notification = NotificationModel.fromJson(message);
      } else if (message is NotificationModel) {
        // Already a notification model
        notification = message;
      } else {
        throw ArgumentError('Invalid notification format: $message');
      }
      
      _notifications.insert(0, notification);
      _isLoading = false;
      _hasError = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      print('Error adding notification: $e');
      _isLoading = false;
      _hasError = true;
      _error = 'Failed to process notification: ${e.toString()}';
      notifyListeners();
    }
  }

  void setConnected(bool connected) {
    _isConnected = connected;
    notifyListeners();
  }

  void disconnect() {
    _isConnected = false;
    _notifications.clear();
    _isLoading = false;
    _hasError = false;
    _error = null;
    notifyListeners();
  }

  void showError(String message) {
    _hasError = true;
    _error = message;
    _isLoading = false;
    notifyListeners();
  }

  void markAsRead(String notificationId) {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);
      notifyListeners();
    } else {
      showError('Notification not found');
    }
  }

  void clearNotifications() {
    _notifications.clear();
    notifyListeners();
  }

  bool get notificationsEnabled => _notificationsEnabled;
  
  void setNotificationsEnabled(bool enabled) {
    _notificationsEnabled = enabled;
    notifyListeners();
  }

  @override
  void dispose() {
    _notifications.clear();
    _hasError = false;
    _error = null;
    super.dispose();
  }
}
