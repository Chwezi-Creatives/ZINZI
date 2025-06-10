//cspell:disable
// This is a stub implementation for flutter_local_notifications on web platform
// It provides empty implementations of the required classes to avoid build errors

// Define the classes that are imported in fcm_service.dart
class AndroidFlutterLocalNotificationsPlugin {}

class AndroidInitializationSettings {
  final String? defaultIcon;
  const AndroidInitializationSettings(this.defaultIcon);
}

class AndroidNotificationChannel {
  final String id;
  final String name;
  final String? description;
  final Importance importance;
  final bool playSound;
  final bool showBadge;
  final bool enableLights;
  final bool enableVibration;

  const AndroidNotificationChannel(this.id, this.name,
      {this.description,
      this.importance = Importance.defaultImportance,
      this.playSound = true,
      this.showBadge = true,
      this.enableLights = false,
      this.enableVibration = true});
}

class AndroidNotificationDetails {
  final String channelId;
  final String channelName;
  final String? channelDescription;
  final Importance importance;
  final Priority priority;
  final bool showWhen;
  final bool playSound;
  final bool enableLights;
  final bool enableVibration;
  final bool fullScreenIntent;

  const AndroidNotificationDetails(this.channelId, this.channelName,
      {this.channelDescription,
      this.importance = Importance.defaultImportance,
      this.priority = Priority.defaultPriority,
      this.showWhen = false,
      this.playSound = true,
      this.enableLights = false,
      this.enableVibration = true,
      this.fullScreenIntent = false});
}

class DarwinInitializationSettings {
  final bool requestAlertPermission;
  final bool requestBadgePermission;
  final bool requestSoundPermission;

  const DarwinInitializationSettings({
    this.requestAlertPermission = true,
    this.requestBadgePermission = true,
    this.requestSoundPermission = true,
  });
}

class FlutterLocalNotificationsPlugin {
  Future<void> initialize(InitializationSettings initializationSettings,
      {Function(dynamic)? onDidReceiveNotificationResponse}) async {}

  Future<void> show(int id, String? title, String? body,
      NotificationDetails? notificationDetails,
      {String? payload}) async {}

  T? resolvePlatformSpecificImplementation<T>() {
    return null;
  }
}

enum Importance {
  none,
  min,
  low,
  defaultImportance,
  high,
  max,
}

class InitializationSettings {
  final AndroidInitializationSettings? android;
  final DarwinInitializationSettings? iOS;

  const InitializationSettings({this.android, this.iOS});
}

class NotificationDetails {
  final AndroidNotificationDetails? android;

  const NotificationDetails({this.android});
}

enum Priority {
  min,
  low,
  defaultPriority,
  high,
  max,
}
