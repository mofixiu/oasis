import 'package:flutter/foundation.dart';
import '../../../core/network/load_failure.dart';
import '../../../core/session/session_scope.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';

class NotificationController extends ChangeNotifier
    with LoadFailureState
    implements SessionScopedController {
  final NotificationService _notificationService;

  NotificationController({NotificationService? notificationService})
    : _notificationService = notificationService ?? NotificationService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<NotificationItemModel> _notifications = [];
  List<NotificationItemModel> get notifications => _notifications;

  // Active filters, mirrored to the backend query params.
  NotificationType? _typeFilter;
  NotificationType? get typeFilter => _typeFilter;

  bool _unreadOnly = false;
  bool get unreadOnly => _unreadOnly;

  bool get hasActiveFilter => _typeFilter != null || _unreadOnly;

  /// Total unread across *all* notifications, independent of the active
  /// filters. The visible list may be a filtered subset, so the app-bar badge
  /// must not be derived from it.
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  /// Distinguishes "never loaded" from "loaded and genuinely empty", so the
  /// first frame after mount or after a session reset shows a skeleton rather
  /// than an inaccurate "you are all caught up".
  bool _hasLoaded = false;
  bool get hasLoaded => _hasLoaded;

  @override
  void resetSessionState() {
    _notifications = [];
    // The badge count is rendered in the app bar on every screen, so a stale
    // value here is the most visible leak of all.
    _unreadCount = 0;
    _typeFilter = null;
    _unreadOnly = false;
    clearFailure();
    _isLoading = false;
    _hasLoaded = false;
    notifyListeners();
  }

  /// Fetch notifications using the current filters.
  Future<void> loadNotifications() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      _notifications = await _notificationService.getNotifications(
        type: _typeFilter,
        isRead: _unreadOnly ? false : null,
      );
      await _refreshUnreadCount();
    } catch (e) {
      captureFailure(e);
    } finally {
      _hasLoaded = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refreshes only the unread badge count. Safe to call on dashboards that
  /// show the bell but not the list itself.
  Future<void> refreshUnreadCount() async {
    try {
      await _refreshUnreadCount();
      notifyListeners();
    } catch (_) {
      // Badge count is non-critical; leave the previous value in place.
    }
  }

  Future<void> _refreshUnreadCount() async {
    // When the visible list is already the complete unfiltered set, reuse it
    // instead of spending a second request.
    if (!hasActiveFilter) {
      _unreadCount = _notifications.where((n) => !n.isRead).length;
      return;
    }
    final unread = await _notificationService.getNotifications(isRead: false);
    _unreadCount = unread.length;
  }

  Future<void> applyFilters({
    NotificationType? type,
    bool? unreadOnly,
    bool clearType = false,
  }) async {
    _typeFilter = clearType ? null : (type ?? _typeFilter);
    _unreadOnly = unreadOnly ?? _unreadOnly;
    await loadNotifications();
  }

  Future<void> clearFilters() async {
    _typeFilter = null;
    _unreadOnly = false;
    await loadNotifications();
  }

  /// Mark notification read
  Future<void> markRead(String notificationId) async {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1 && _notifications[index].isRead) return;

    try {
      final updated = await _notificationService.markNotificationRead(
        notificationId,
      );
      if (index != -1) {
        // Under an unread-only filter the item no longer belongs in the list.
        if (_unreadOnly) {
          _notifications.removeAt(index);
        } else {
          _notifications[index] = updated;
        }
      }
      if (_unreadCount > 0) _unreadCount--;
      notifyListeners();
    } catch (e) {
      captureFailure(e);
      notifyListeners();
    }
  }

  /// Marks every currently-unread notification as read.
  Future<void> markAllRead() async {
    final unread = _notifications.where((n) => !n.isRead).toList();
    if (unread.isEmpty) return;

    _isLoading = true;
    notifyListeners();
    try {
      for (final item in unread) {
        await _notificationService.markNotificationRead(item.id);
      }
      await loadNotifications();
    } catch (e) {
      captureFailure(e);
      _isLoading = false;
      notifyListeners();
    }
  }
}
