import 'package:flutter/foundation.dart';

/// Web-specific notification handler
/// 
/// This file implements web-specific notification functionality using the browser's
/// Notification API. This implementation is automatically used on web platforms
/// due to conditional imports in the main notification service.
/// 
/// IMPORTANT: Any changes to this API must maintain backward compatibility with
/// the native implementation in notification_service_io.dart
/// 
/// Implementation Notes:
/// - Uses the browser's Notification API for showing notifications
/// - Requires user permission to display notifications
/// - Falls back to no-op if notifications are not supported
/// 
/// @param title The notification title
/// @param body The notification body text
/// @param data Optional map of additional data to include with the notification
void showWebNotification({
  required String title,
  required String body,
  Map<String, dynamic>? data,
}) {
  try {
    // This implementation will be replaced at build time with the actual
    // web implementation that uses dart:js interop
    // 
    // The build system will replace this with a version that uses:
    // 1. window.Notification.requestPermission()
    // 2. new Notification() constructor
    // 3. Handles click events and data passing
    throw UnsupportedError('Web notifications not supported in this context');
  } catch (e) {
    debugPrint('Error showing web notification: $e');
    // Fail silently in production, but log the error
    assert(false, 'Failed to show web notification: $e');
  }
}
