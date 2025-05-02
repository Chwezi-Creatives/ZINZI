enum NotificationType {
  order,
  chef,
  producer,
  transporter,
  social,
  blog,
  system,
}

enum NotificationSeverity {
  info,
  warning,
  error,
  success,
}

class NotificationModel {
  final String id;
  final NotificationType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime createdAt;
  final bool isRead;
  final NotificationSeverity severity;

  NotificationModel({
    required this.id,
    required this.type,
    required this.message,
    this.data,
    required this.createdAt,
    this.isRead = false,
    this.severity = NotificationSeverity.info,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    final severity = json['severity'];
    
    return NotificationModel(
      id: json['id'],
      type: type is int ? NotificationType.values[type] : NotificationType.order,
      message: json['message'] ?? '',
      data: json['data'] is Map ? json['data'] : null,
      createdAt: DateTime.parse(json['created_at']),
      isRead: json['is_read'] ?? false,
      severity: severity is int ? NotificationSeverity.values[severity] : NotificationSeverity.info,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.index,
      'message': message,
      'data': data,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
      'severity': severity.index,
    };
  }

  NotificationModel copyWith({
    String? id,
    NotificationType? type,
    String? message,
    dynamic data,
    DateTime? createdAt,
    bool? isRead,
    NotificationSeverity? severity,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      type: type ?? this.type,
      message: message ?? this.message,
      data: data ?? this.data,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      severity: severity ?? this.severity,
    );
  }
}
