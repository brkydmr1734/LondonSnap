import 'package:flutter/material.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/core/config/app_config.dart';
import 'package:londonsnaps/core/errors/app_exceptions.dart';
import 'package:londonsnaps/core/errors/error_handler.dart';
import 'package:londonsnaps/core/services/push_notification_service.dart';
import 'package:londonsnaps/shared/models/user.dart';

class AuthProvider extends ChangeNotifier {
  static final AuthProvider _instance = AuthProvider._internal();
  factory AuthProvider() => _instance;
  AuthProvider._internal() {
    // When API detects expired tokens (401 + refresh fail), force logout.
    _api.onAuthExpired = _forceLogout;
  }

  final ApiService _api = ApiService();
  final PushNotificationService _pushService = PushNotificationService();

  User? _currentUser;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _error;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get error => _error;

  Future<void> checkAuthState() async {
    final hasToken = await _api.hasToken();
    if (hasToken) {
      try {
        final response = await _api.getCurrentUser();
        _currentUser = User.fromJson(response.data['data']['user']);
        _isAuthenticated = true;
      } catch (e) {
        _isAuthenticated = false;
        await _api.clearTokens();
      }
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      if (AppConfig.isDev) debugPrint('[AUTH] Login attempt: $email');
      final response = await _api.login(email, password);
      final data = response.data['data'];
      await _api.saveTokens(data['accessToken'], data['refreshToken']);
      _currentUser = User.fromJson(data['user']);
      _isAuthenticated = true;
      _isLoading = false;
      notifyListeners();
      
      // Register for push notifications
      _registerForPushNotifications();
      
      return true;
    } catch (e) {
      final ex = e is AppException ? e : ErrorHandler.handle(e);
      if (AppConfig.isDev) debugPrint('[AUTH] Login error: $ex');
      _error = ex.message;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String email, required String password,
    required String username, required String displayName,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await _api.register(
        email: email, password: password,
        username: username, displayName: displayName,
      );
      final data = response.data['data'];
      await _api.saveTokens(data['accessToken'], data['refreshToken']);
      _currentUser = User.fromJson(data['user']);
      _isAuthenticated = true;
      _isLoading = false;
      notifyListeners();
      
      // Register for push notifications
      _registerForPushNotifications();
      
      return true;
    } catch (e) {
      final ex = e is AppException ? e : ErrorHandler.handle(e);
      _error = ex.message;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> socialAuth({
    required String provider, required String providerId,
    String? email, String? displayName, String? avatarUrl,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await _api.socialAuth(
        provider: provider, providerId: providerId,
        email: email, displayName: displayName, avatarUrl: avatarUrl,
      );
      final data = response.data['data'];
      await _api.saveTokens(data['accessToken'], data['refreshToken']);
      _currentUser = User.fromJson(data['user']);
      _isAuthenticated = true;
      _isLoading = false;
      notifyListeners();
      
      // Register for push notifications
      _registerForPushNotifications();
      
      return true;
    } catch (e) {
      final ex = e is AppException ? e : ErrorHandler.handle(e);
      _error = ex.message;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> requestPasswordReset(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _api.requestPasswordReset(email);
    } catch (e) {
      final ex = e is AppException ? e : ErrorHandler.handle(e);
      _error = ex.message;
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> resetPassword(String email, String code, String newPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _api.resetPassword(email, code, newPassword);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      final ex = e is AppException ? e : ErrorHandler.handle(e);
      _error = ex.message;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    // 1. Call backend to invalidate the session server-side
    try {
      await _api.logoutFromServer();
    } catch (_) {
      // Best-effort — continue local cleanup even if backend call fails
    }

    // 2. Clear push notification registration
    try {
      await _pushService.clearUser();
    } catch (_) {}

    // 3. Clear local tokens & state
    await _api.clearTokens();
    _currentUser = null;
    _isAuthenticated = false;
    _error = null;
    notifyListeners();
  }

  /// Called by ApiService when token refresh fails (automatic 401 handling).
  void _forceLogout() {
    _currentUser = null;
    _isAuthenticated = false;
    _error = null;
    notifyListeners();
  }

  /// Register current user for push notifications via FCM.
  void _registerForPushNotifications() {
    if (_currentUser != null) {
      // This registers the FCM token with the backend for SNS delivery
      _pushService.registerUser(_currentUser!.id);
    }
  }
}
