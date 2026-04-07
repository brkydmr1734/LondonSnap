import 'package:flutter/material.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/core/config/app_config.dart';
import 'package:londonsnaps/core/errors/app_exceptions.dart';
import 'package:londonsnaps/core/errors/error_handler.dart';
import 'package:londonsnaps/shared/models/notification.dart';

class NotificationProvider extends ChangeNotifier {
  // Singleton so all screens share the same notification state.
  static final NotificationProvider _instance = NotificationProvider._internal();
  factory NotificationProvider() => _instance;
  NotificationProvider._internal();

  final ApiService _api = ApiService();

  List<AppNotification> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  bool _hasMore = true;

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _hasMore;

  /// Fetch notifications from API.
  Future<void> fetchNotifications({bool refresh = false}) async {
    if (_isLoading) return;

    if (refresh) {
      _notifications = [];
      _hasMore = true;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.getNotifications(limit: 50, offset: 0);
      final data = response.data['data'];

      _notifications = (data['notifications'] as List)
          .map((json) => AppNotification.fromJson(json))
          .toList();
      _unreadCount = data['unreadCount'] as int;
      _hasMore = _notifications.length >= 50;

      if (AppConfig.isDev) {
        debugPrint('[Notifications] Fetched ${_notifications.length}, unread: $_unreadCount');
      }
    } catch (e) {
      final ex = e is AppException ? e : ErrorHandler.handle(e);
      _error = ex.message;
      if (AppConfig.isDev) debugPrint('[Notifications] Fetch error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load more notifications for pagination.
  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final response = await _api.getNotifications(
        limit: 50,
        offset: _notifications.length,
      );
      final data = response.data['data'];

      final newNotifications = (data['notifications'] as List)
          .map((json) => AppNotification.fromJson(json))
          .toList();

      _notifications.addAll(newNotifications);
      _hasMore = newNotifications.length >= 50;
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[Notifications] Load more error: $e');
    }

    _isLoadingMore = false;
    notifyListeners();
  }

  /// Mark a single notification as read.
  Future<void> markAsRead(String notificationId) async {
    try {
      await _api.markNotificationAsRead(notificationId);

      final index = _notifications.indexWhere((n) => n.id == notificationId);
      if (index != -1 && !_notifications[index].isRead) {
        _notifications[index] = _notifications[index].copyWith(isRead: true);
        _unreadCount = (_unreadCount - 1).clamp(0, _unreadCount);
        notifyListeners();
      }
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[Notifications] Mark read error: $e');
    }
  }

  /// Mark all notifications as read.
  Future<void> markAllAsRead() async {
    try {
      await _api.markAllNotificationsAsRead();

      _notifications = _notifications
          .map((n) => n.copyWith(isRead: true))
          .toList();
      _unreadCount = 0;
      notifyListeners();
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[Notifications] Mark all read error: $e');
    }
  }

  /// Delete a notification.
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _api.deleteNotification(notificationId);

      final notification = _notifications.firstWhere(
        (n) => n.id == notificationId,
        orElse: () => throw Exception('Not found'),
      );

      _notifications.removeWhere((n) => n.id == notificationId);
      if (!notification.isRead) {
        _unreadCount = (_unreadCount - 1).clamp(0, _unreadCount);
      }
      notifyListeners();
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[Notifications] Delete error: $e');
    }
  }

  /// Clear all notifications.
  Future<void> clearAll() async {
    try {
      await _api.clearAllNotifications();
      _notifications = [];
      _unreadCount = 0;
      notifyListeners();
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[Notifications] Clear all error: $e');
    }
  }

  /// Add a notification from push (for in-app display).
  void addFromPush(Map<String, dynamic> pushData) {
    try {
      // Create notification from push payload
      final notification = AppNotification(
        id: pushData['notificationId'] ?? DateTime.now().toIso8601String(),
        type: NotificationType.fromString(pushData['type'] ?? 'MESSAGE'),
        title: pushData['title'] ?? '',
        body: pushData['body'] ?? '',
        imageUrl: pushData['imageUrl'],
        data: pushData['data'],
        isRead: false,
        createdAt: DateTime.now(),
      );

      // Add to front of list
      _notifications.insert(0, notification);
      _unreadCount++;
      notifyListeners();
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[Notifications] Add from push error: $e');
    }
  }

  /// Update unread count (e.g., from push notification).
  void incrementUnreadCount() {
    _unreadCount++;
    notifyListeners();
  }
}
