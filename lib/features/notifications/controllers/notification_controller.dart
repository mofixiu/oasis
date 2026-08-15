import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';

class NotificationController extends ChangeNotifier {
  final NotificationService _notificationService;

  NotificationController({NotificationService? notificationService})
      : _notificationService = notificationService ?? NotificationService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<NotificationItemModel> _notifications = [];
  List<NotificationItemModel> get notifications => _notifications;

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Fetch notifications
  Future<void> loadNotifications() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _notifications = await _notificationService.getNotifications();
    } catch (e) {
      _errorMessage = friendlyErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Mark notification read
  Future<void> markRead(String notificationId) async {
    try {
      final updated = await _notificationService.markNotificationRead(notificationId);
      final index = _notifications.indexWhere((n) => n.id == notificationId);
      if (index != -1) {
        _notifications[index] = updated;
        notifyListeners();
      }
    } catch (_) {}
  }
}
