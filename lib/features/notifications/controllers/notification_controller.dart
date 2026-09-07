import 'package:flutter/foundation.dart';
import '../../../core/network/load_failure.dart';
import '../../../core/session/session_scope.dart';
import '../models/broadcast_model.dart';
import '../models/notification_model.dart';
import '../services/broadcast_service.dart';
import '../services/notification_service.dart';

class NotificationController extends ChangeNotifier
    with LoadFailureState
    implements SessionScopedController {
  final NotificationService _notificationService;
  final BroadcastService _broadcastService;

  NotificationController({
    NotificationService? notificationService,
    BroadcastService? broadcastService,
  }) : _notificationService = notificationService ?? NotificationService(),
       _broadcastService = broadcastService ?? BroadcastService();

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

  /// Broadcasts this landlord has sent. Empty for tenants, who never send any.
  List<Broadcast> _broadcasts = [];
  List<Broadcast> get broadcasts => _broadcasts;

  bool _isSendingBroadcast = false;
  bool get isSendingBroadcast => _isSendingBroadcast;

  NotificationPreferences? _preferences;

  /// Whether the user wants the optional 180/90/30-day rent reminder emails.
  ///
  /// Null until read. The switch shows the last known value while a change is
  /// in flight rather than flicking back and forth, so this is only ever set
  /// from the backend's own answer.
  bool? get earlyRentReminderEmails => _preferences?.earlyRentReminderEmails;

  // `push_notifications_enabled` is read and parsed by
  // [NotificationPreferences] but deliberately not surfaced: the app sends no
  // device token, so phone push does not happen and a setting for it would be
  // a switch over nothing. Out of MVP scope — see
  // `backend docs/backend_change_spec_v15.md` §3.

  bool _isSavingPreferences = false;
  bool get isSavingPreferences => _isSavingPreferences;

  /// Every notification id this session has seen, whether it is still in the
  /// visible (possibly filtered) list or not.
  ///
  /// The visible list cannot answer "is this new?": it is filtered, it is
  /// truncated by the backend's own page size, and marking something read
  /// removes it under an unread-only filter. Popping a banner for something
  /// the user has already seen is worse than not popping one at all, so the
  /// question gets its own record.
  final Set<String> _knownIds = {};

  /// Whether [pollForNewNotifications] has established what "already seen"
  /// means. Until it has, everything unread looks new, and a user opening
  /// the app to eleven unread notifications does not want eleven banners.
  bool _pollBaselineSet = false;

  @override
  void resetSessionState() {
    _notifications = [];
    _broadcasts = [];
    _knownIds.clear();
    _pollBaselineSet = false;
    _isSendingBroadcast = false;
    // The badge count is rendered in the app bar on every screen, so a stale
    // value here is the most visible leak of all.
    _unreadCount = 0;
    _typeFilter = null;
    _unreadOnly = false;
    _preferences = null;
    _isSavingPreferences = false;
    clearFailure();
    _isLoading = false;
    _hasLoaded = false;
    notifyListeners();
  }

  /// Reads the user's notification preferences.
  ///
  /// Failure is deliberately quiet: this is a settings row, not the reason the
  /// user opened the screen, and an error banner over their profile for a
  /// switch they were not looking at would be noise.
  Future<void> loadPreferences() async {
    try {
      _preferences = await _notificationService.getPreferences();
      notifyListeners();
    } catch (e) {
      debugPrint('[NOTIFICATIONS] Could not read preferences: $e');
    }
  }

  /// Turns the early rent reminder emails on or off. Returns true when saved.
  ///
  /// The switch is only moved once the backend confirms: an optimistic flip
  /// that then fails would leave someone believing they had unsubscribed.
  Future<bool> setEarlyRentReminderEmails(bool enabled) =>
      _savePreference(earlyRentReminderEmails: enabled);

  Future<bool> _savePreference({bool? earlyRentReminderEmails}) async {
    _isSavingPreferences = true;
    clearFailure();
    notifyListeners();

    try {
      _preferences = await _notificationService.setPreferences(
        earlyRentReminderEmails: earlyRentReminderEmails,
      );
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isSavingPreferences = false;
      notifyListeners();
    }
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
      _knownIds.addAll(_notifications.map((n) => n.id));
      // A full load is a baseline in its own right: everything it returned is
      // on screen, so nothing in it deserves a banner.
      _pollBaselineSet = true;
      await _refreshUnreadCount();
    } catch (e) {
      captureFailure(e);
    } finally {
      _hasLoaded = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Files a notification pushed down the realtime socket.
  ///
  /// The list is patched rather than refetched: the payload is the same shape
  /// the REST endpoint serves, and a full reload on every arrival would make
  /// a burst of them, a landlord approving six applications, six round
  /// trips for information already in hand.
  ///
  /// Returns the notification when it is genuinely new, so the caller can
  /// decide whether to interrupt the user with a popup. Null means it was a
  /// duplicate, or it does not belong in the list the user is currently
  /// filtered to.
  NotificationItemModel? applyIncomingNotification(Map<String, dynamic> json) {
    final notification = NotificationItemModel.fromJson(json);
    if (notification.id.isEmpty) return null;
    // Sockets reconnect, and a server that replays what it thinks was missed
    // will resend. An id already held is not a second event.
    if (!_knownIds.add(notification.id)) return null;

    if (!notification.isRead) _unreadCount++;

    // Respect whatever the user has narrowed the list to. The badge still
    // moves, it counts everything, but a notification that does not match
    // the active filter must not appear in a filtered list, or the filter
    // reads as broken.
    final matchesType = _typeFilter == null || notification.type == _typeFilter;
    final matchesRead = !_unreadOnly || !notification.isRead;
    if (matchesType && matchesRead) {
      _notifications = [notification, ..._notifications];
    }

    notifyListeners();
    return notification;
  }

  /// Asks what is unread and returns whatever has appeared since last time.
  ///
  /// The fallback path for in-app popups. When the realtime socket is up
  /// nothing calls this: a pushed `notification.created` is both cheaper and
  /// instant. It exists because the socket is a backend change that has not
  /// shipped yet (`backend_change_spec_v11.md` §1), and a notification the
  /// user only discovers by opening the bell is not a notification.
  ///
  /// Only *unread* rows are asked for: it is one small request, and a
  /// notification the user has already read is by definition not news.
  ///
  /// The first call after a session starts returns nothing and only records
  /// what is already there. Opening the app to eleven unread notifications
  /// should not produce eleven banners.
  ///
  /// Quiet on failure: the same reasoning as the badge count.
  Future<List<NotificationItemModel>> pollForNewNotifications() async {
    try {
      final unread = await _notificationService.getNotifications(isRead: false);
      final fresh = unread.where((n) => !_knownIds.contains(n.id)).toList();
      _knownIds.addAll(unread.map((n) => n.id));
      _unreadCount = unread.length;

      final wasSeeded = _pollBaselineSet;
      _pollBaselineSet = true;

      // Filed into the visible list only when the user is looking at the
      // unfiltered one. Under a filter the badge still moves, but the list
      // stays as narrowed as they left it.
      if (fresh.isNotEmpty && !hasActiveFilter) {
        _notifications = [...fresh, ..._notifications];
      }
      notifyListeners();
      return wasSeeded ? fresh : const [];
    } catch (e) {
      debugPrint('[NOTIFICATIONS] Poll failed: $e');
      return const [];
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
  /// Marks one notification read, on screen first.
  ///
  /// Nothing about reading a notification is in doubt, and the badge is the
  /// most-looked-at number in the app: leaving it stale for the length of a
  /// round trip, on a list somebody is tapping through quickly, made the
  /// count look broken. So the row and the badge change immediately and the
  /// request follows.
  Future<void> markRead(String notificationId) async {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1 && _notifications[index].isRead) return;

    final previous = index == -1 ? null : _notifications[index];
    final previousCount = _unreadCount;
    if (previous != null) {
      // Under an unread-only filter the item no longer belongs in the list.
      if (_unreadOnly) {
        _notifications.removeAt(index);
      } else {
        _notifications[index] = previous.copyWithRead();
      }
    }
    if (_unreadCount > 0) _unreadCount--;
    notifyListeners();

    try {
      final updated = await _notificationService.markNotificationRead(
        notificationId,
      );
      // Reconciled with the server's copy where the row is still on screen.
      final at = _notifications.indexWhere((n) => n.id == notificationId);
      if (at != -1) _notifications[at] = updated;
      notifyListeners();
    } catch (e) {
      // Put it back. An unread notification silently marked read is one the
      // user never sees again.
      if (previous != null) {
        if (_unreadOnly) {
          _notifications.insert(
            index.clamp(0, _notifications.length),
            previous,
          );
        } else {
          final at = _notifications.indexWhere((n) => n.id == notificationId);
          if (at != -1) _notifications[at] = previous;
        }
      }
      _unreadCount = previousCount;
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

  /// Loads the landlord's sent broadcasts.
  Future<void> loadBroadcasts() async {
    try {
      _broadcasts = await _broadcastService.getBroadcasts();
    } catch (e) {
      captureFailure(e);
    }
    notifyListeners();
  }

  /// Sends an announcement to the landlord's tenants.
  ///
  /// Returns the sent broadcast, or null on failure: the caller shows
  /// [errorMessage], which carries the backend's reason (no tenants yet, daily
  /// limit reached, body too long).
  Future<Broadcast?> sendBroadcast({
    required BroadcastAudience audience,
    required String title,
    required String body,
    String? propertyId,
  }) async {
    _isSendingBroadcast = true;
    clearFailure();
    notifyListeners();

    try {
      final broadcast = await _broadcastService.sendBroadcast(
        audience: audience,
        title: title,
        body: body,
        propertyId: propertyId,
      );
      _broadcasts = [broadcast, ..._broadcasts];
      return broadcast;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isSendingBroadcast = false;
      notifyListeners();
    }
  }
}
