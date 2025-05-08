import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'notification_provider.dart';
import 'notification_panel.dart';

class GlobalNotificationBadge extends StatelessWidget {
  const GlobalNotificationBadge({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final notificationProvider = context.watch<NotificationProvider>();
    final unreadCount = notificationProvider.notifications.where((n) => !n.isRead).length;

    if (unreadCount == 0) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 40, // Adjust as needed for your app's UI
      right: 16,
      child: GestureDetector(
        onTap: () => showNotificationPanel(context),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.notifications, size: 32, color: Colors.teal),
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
