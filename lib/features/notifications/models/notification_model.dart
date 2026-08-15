class NotificationItemModel {
  final String id;
  final String notificationType;
  final String message;
  final bool isRead;
  final String createdAt;

  NotificationItemModel({
    required this.id,
    required this.notificationType,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationItemModel.fromJson(Map<String, dynamic> json) {
    return NotificationItemModel(
      id: json['id'] ?? '',
      notificationType: json['notification_type'] ?? '',
      message: json['message'] ?? '',
      isRead: json['is_read'] ?? false,
      createdAt: json['created_at'] ?? '',
    );
  }
}
