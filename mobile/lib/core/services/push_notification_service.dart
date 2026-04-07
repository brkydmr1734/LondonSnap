import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/core/config/app_config.dart';

/// Callback type for handling foreground push notifications.
typedef OnNotificationReceived = void Function(Map<String, dynamic> notification);

/// Service for managing Firebase Cloud Messaging push notifications.
/// FCM tokens are registered with the backend (AWS SNS) for delivery.
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._();
  factory PushNotificationService() => _instance;
  PushNotificationService._();

  FirebaseMessaging? _messaging;
  final ApiService _api = ApiService();
  bool _firebaseAvailable = false;
  
  bool _isInitialized = false;
  String? _currentUserId;
  String? _fcmToken;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;

  /// Callback to handle foreground notifications (show in-app banner).
  OnNotificationReceived? onNotificationReceived;

  /// Callback for deep link navigation from notification tap.
  void Function(String type, Map<String, dynamic> data)? onNotificationTapped;

  /// Initialize Firebase Messaging.
  /// Call this early in app startup (after Firebase.initializeApp).
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _messaging = FirebaseMessaging.instance;
      _firebaseAvailable = true;
    } catch (e) {
      debugPrint('[PushNotifications] Firebase not available, push disabled: $e');
      _isInitialized = true;
      return;
    }

    try {
      // Request permission (iOS primarily, Android 13+ also requires)
      final settings = await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
      );

      if (AppConfig.isDev) {
        debugPrint('[PushNotifications] Permission status: ${settings.authorizationStatus}');
      }

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // Get FCM token
        _fcmToken = await _messaging!.getToken();
        if (AppConfig.isDev) {
          debugPrint('[PushNotifications] FCM Token: $_fcmToken');
        }

        // Listen for token refresh
        _tokenRefreshSubscription = _messaging!.onTokenRefresh.listen(_onTokenRefresh);
      }

      // Handle foreground messages
      _foregroundSubscription = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle background/terminated message taps (when user taps notification)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

      // Check if app was opened from a terminated state notification
      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        if (AppConfig.isDev) {
          debugPrint('[PushNotifications] App opened from terminated via notification');
        }
        // Delay to ensure navigation is ready
        Future.delayed(const Duration(milliseconds: 500), () {
          _handleMessageTap(initialMessage);
        });
      }

      _isInitialized = true;

      if (AppConfig.isDev) {
        debugPrint('[PushNotifications] Initialized successfully');
      }
    } catch (e) {
      debugPrint('[PushNotifications] Failed to initialize: $e');
    }
  }

  /// Register the current user for push notifications.
  /// Call this after successful login.
  Future<void> registerUser(String userId) async {
    _currentUserId = userId;
    if (!_firebaseAvailable) return;

    if (_fcmToken == null) {
      // Try to get token again
      try {
        _fcmToken = await _messaging!.getToken();
      } catch (e) {
        debugPrint('[PushNotifications] Failed to get FCM token: $e');
        return;
      }
    }

    if (_fcmToken != null) {
      await _registerTokenWithBackend(_fcmToken!);
    }
  }

  /// Handle token refresh - re-register with backend.
  void _onTokenRefresh(String newToken) {
    _fcmToken = newToken;
    if (AppConfig.isDev) {
      debugPrint('[PushNotifications] Token refreshed: $newToken');
    }
    
    // Only register if we have a logged-in user
    if (_currentUserId != null) {
      _registerTokenWithBackend(newToken);
    }
  }

  /// Register FCM token with backend for SNS endpoint creation.
  Future<void> _registerTokenWithBackend(String token) async {
    try {
      final platform = Platform.isIOS ? 'IOS' : 'ANDROID';
      await _api.registerDeviceToken(token, platform);
      
      if (AppConfig.isDev) {
        debugPrint('[PushNotifications] Registered token with backend (platform: $platform)');
      }
    } catch (e) {
      debugPrint('[PushNotifications] Failed to register token with backend: $e');
    }
  }

  /// Handle foreground push notification.
  void _handleForegroundMessage(RemoteMessage message) {
    try {
      if (AppConfig.isDev) {
        debugPrint('[PushNotifications] Foreground message received');
        debugPrint('[PushNotifications] Title: ${message.notification?.title}');
        debugPrint('[PushNotifications] Body: ${message.notification?.body}');
        debugPrint('[PushNotifications] Data: ${message.data}');
      }

      // Build notification data for callback
      final notification = <String, dynamic>{
        'title': message.notification?.title ?? '',
        'body': message.notification?.body ?? '',
        'type': message.data['type'] ?? 'MESSAGE',
        'notificationId': message.data['notificationId'] ?? message.messageId,
        ...message.data,
      };

      // Invoke callback if set (for in-app banner display)
      onNotificationReceived?.call(notification);
    } catch (e) {
      debugPrint('[PushNotifications] Error handling foreground message: $e');
    }
  }

  /// Handle notification tap (from background or terminated state).
  void _handleMessageTap(RemoteMessage message) {
    try {
      if (AppConfig.isDev) {
        debugPrint('[PushNotifications] Message tap - navigating');
        debugPrint('[PushNotifications] Data: ${message.data}');
      }

      final type = message.data['type'] as String? ?? 'MESSAGE';
      final data = Map<String, dynamic>.from(message.data);

      // Invoke tap callback if set
      onNotificationTapped?.call(type, data);
    } catch (e) {
      debugPrint('[PushNotifications] Error handling message tap: $e');
    }
  }

  /// Clear user and unregister device from push notifications.
  /// Call this on logout.
  Future<void> clearUser() async {
    if (!_firebaseAvailable) return;
    try {
      // Unregister from backend
      await _api.unregisterDeviceToken();
      
      if (AppConfig.isDev) {
        debugPrint('[PushNotifications] Unregistered device from backend');
      }
    } catch (e) {
      debugPrint('[PushNotifications] Failed to unregister from backend: $e');
    }

    try {
      // Delete local FCM token
      await _messaging!.deleteToken();
      _fcmToken = null;
      _currentUserId = null;

      if (AppConfig.isDev) {
        debugPrint('[PushNotifications] FCM token deleted, user cleared');
      }
    } catch (e) {
      debugPrint('[PushNotifications] Failed to delete FCM token: $e');
    }
  }

  /// Get deep link destination from notification type.
  String? getDeepLinkPath(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'MESSAGE':
        final chatId = data['chatId'];
        return chatId != null ? '/chats/$chatId' : '/chats';
      case 'SNAP_RECEIVED':
      case 'SNAP_OPENED':
      case 'SNAP_SCREENSHOT':
        return '/camera';
      case 'FRIEND_REQUEST':
      case 'FRIEND_ACCEPTED':
        return '/friends';
      case 'STORY_REACTION':
      case 'STORY_REPLY':
        return '/stories';
      case 'EVENT_INVITE':
      case 'EVENT_REMINDER':
        final eventId = data['eventId'];
        return eventId != null ? '/discover/event/$eventId' : '/discover';
      case 'STREAK_WARNING':
      case 'STREAK_LOST':
        final friendId = data['friendId'];
        return friendId != null ? '/profile/$friendId' : '/friends';
      default:
        return null;
    }
  }

  /// Dispose subscriptions (call if needed on app termination).
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _foregroundSubscription?.cancel();
  }

  /// Whether push notifications are initialized and ready.
  bool get isInitialized => _isInitialized;

  /// Current registered user ID.
  String? get currentUserId => _currentUserId;

  /// Current FCM token.
  String? get fcmToken => _fcmToken;
}

/// Background message handler - must be a top-level function.
/// Called when app is in background or terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Note: Firebase.initializeApp() should already be called if using
  // the background handler. For heavy processing, ensure Firebase is initialized.
  if (kDebugMode) {
    debugPrint('[PushNotifications] Background message: ${message.messageId}');
    debugPrint('[PushNotifications] Data: ${message.data}');
  }
  
  // Background messages are handled by the system notification tray.
  // When user taps, onMessageOpenedApp or getInitialMessage handles navigation.
}
