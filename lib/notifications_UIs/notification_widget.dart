//cspell:disable
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_provider.dart';
import 'notification_model.dart';
import 'notification_panel.dart';

class NotificationWidget extends StatelessWidget {
  final Color iconColor;
  final bool showCounter;
  final int notificationCount;
  final String targetUserType;

  const NotificationWidget({
    Key? key,
    this.iconColor = Colors.white,
    this.showCounter = false,
    this.notificationCount = 0,
    this.targetUserType = '',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (showCounter) {
      // Notification bell with badge/counter
      return Consumer<NotificationProvider>(
        builder: (context, provider, child) {
          final unreadCount = notificationCount > 0
              ? notificationCount
              : provider.unreadCount;
          return GestureDetector(
            onTap: () => showNotificationPanel(context),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.notifications, color: iconColor, size: 28),
                if (unreadCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    }
    // Default: show full notification list (as before)
    return Consumer<NotificationProvider>(
      builder: (context, provider, child) {
        final notifications = provider.notifications;
        if (notifications.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'No notifications yet',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),
            ),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: notifications.length,
          itemBuilder: (context, index) {
            final notification = notifications[index];
            return ListTile(
              leading: Icon(
                _getIconForType(notification.type),
                color: _getColorForType(notification.type),
              ),
              title: Text(notification.message),
              subtitle: Text(
                _formatTimestamp(notification.timestamp),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              trailing: notification.isRead
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : const Icon(Icons.circle, color: Colors.red),
              onTap: () async {
                provider.markAsRead(notification.id);
                if (notification.type == 'order_status_changed') {
                  final prefs = await SharedPreferences.getInstance();
                  final userType = prefs.getString('UserType') ?? 'user';
                  if (userType == 'chef') {
                    Navigator.pushNamed(
                      context,
                      '/chef_orders',
                      arguments: notification.data,
                    );
                  } else if (userType == 'producer') {
                    Navigator.pushNamed(
                      context,
                      '/producer_orders',
                      arguments: notification.data,
                    );
                  } else if (userType == 'transporter') {
                    Navigator.pushNamed(
                      context,
                      '/transporter_orders',
                      arguments: notification.data,
                    );
                  } else {
                    Navigator.pushNamed(
                      context,
                      '/order_details',
                      arguments: notification.data,
                    );
                  }
                }
              },
            );
          },
        );
      },
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'order_status_changed':
        return Icons.local_shipping;
      case 'order':
        return Icons.shopping_cart;
      case 'chef':
        return Icons.restaurant;
      case 'producer':
        return Icons.agriculture;
      case 'transporter':
        return Icons.directions_car;
      case 'social':
        return Icons.people;
      case 'blog':
        return Icons.article;
      case 'system':
        return Icons.info;
      default:
        return Icons.notifications;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'order_status_changed':
        return Colors.blue;
      case 'order':
        return Colors.orange;
      case 'chef':
        return Colors.red;
      case 'producer':
        return Colors.green;
      case 'transporter':
        return Colors.purple;
      case 'social':
        return Colors.pink;
      case 'blog':
        return Colors.teal;
      case 'system':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return timestamp.toString().split('.')[0];
    }
  }
}
