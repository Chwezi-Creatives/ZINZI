import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'notification_provider.dart';
import 'websocket_service.dart';
import 'notification_model.dart';
import 'notification_feedback_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationWidget extends StatefulWidget {
  final NotificationModel notification;

  const NotificationWidget({
    Key? key,
    required this.notification,
  }) : super(key: key);

  @override
  _NotificationWidgetState createState() => _NotificationWidgetState();
}

class _NotificationWidgetState extends State<NotificationWidget> {
  late WebSocketService _webSocketService;
  late NotificationFeedbackService _feedbackService;
  late NotificationProvider _notificationProvider;
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    _prefs = await SharedPreferences.getInstance();
    _notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
    _feedbackService = NotificationFeedbackService(_prefs);
    _webSocketService = WebSocketService(_notificationProvider);
    _setupWebSocket();
  }

  @override
  void dispose() {
    _webSocketService.disconnect();
    _feedbackService.dispose();
    super.dispose();
  }

  void _setupWebSocket() {
    try {
      _webSocketService.connect();
      _webSocketService.channel.stream.listen(
        (message) {
          _feedbackService.giveFeedback();
          setState(() {
            _notificationProvider.addNotification(message);
          });
        },
        onError: (error) {
          print('WebSocket error: $error');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Connection error: $error')),
            );
          }
        },
        onDone: () {
          print('WebSocket connection closed');
          // Attempt to reconnect after a delay
          Future.delayed(Duration(seconds: 5), () {
            if (mounted) {
              _setupWebSocket();
            }
          });
        }
      );
    } catch (e) {
      print('Failed to setup WebSocket: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect: $e')),
        );
      }
    }
  }

  Color _getSeverityColor(NotificationSeverity severity) {
    switch (severity) {
      case NotificationSeverity.info:
        return Colors.blue;
      case NotificationSeverity.warning:
        return Colors.orange;
      case NotificationSeverity.error:
        return Colors.red;
      case NotificationSeverity.success:
        return Colors.green;
    }
  }

  IconData _getSeverityIcon(NotificationSeverity severity) {
    switch (severity) {
      case NotificationSeverity.info:
        return Icons.info;
      case NotificationSeverity.warning:
        return Icons.warning;
      case NotificationSeverity.error:
        return Icons.error;
      case NotificationSeverity.success:
        return Icons.check_circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: Icon(
          _getSeverityIcon(widget.notification.severity),
          color: _getSeverityColor(widget.notification.severity),
        ),
        title: Text(
          widget.notification.message,
          style: TextStyle(
            color: widget.notification.isRead ? Colors.grey : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.notification.data != null)
              Text(
                widget.notification.data.toString(),
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            Text(
              _formatTime(widget.notification.createdAt),
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontSize: 12,
              ),
            ),
          ],
        ),
        onTap: () {
          // Handle notification tap
        },
      ),
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'order_created':
        return Icons.shopping_cart;
      case 'order_status_changed':
        return Icons.notifications;
      case 'order_assigned':
        return Icons.assignment;
      default:
        return Icons.notifications;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'order_created':
        return Colors.green;
      case 'order_status_changed':
        return Colors.blue;
      case 'order_assigned':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inDays} days ago';
    }
  }
}
