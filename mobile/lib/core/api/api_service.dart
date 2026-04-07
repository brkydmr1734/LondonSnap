import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:londonsnaps/core/config/app_config.dart';
import 'package:londonsnaps/core/errors/error_handler.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;
  late final Dio _refreshDio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _isRefreshing = false;

  String? _cachedAccessToken;
  String? _cachedRefreshToken;

  static const _publicAuthPaths = {
    '/auth/login', '/auth/register', '/auth/social',
    '/auth/send-code', '/auth/verify-code', '/auth/forgot-password',
    '/auth/refresh', '/auth/password/reset-request', '/auth/password/reset',
  };

  ApiService._internal() {
    final baseOpts = BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      sendTimeout: AppConfig.sendTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Accept-Encoding': 'gzip',
        'Connection': 'keep-alive',
      },
      persistentConnection: true,
    );

    _dio = Dio(baseOpts);
    _refreshDio = Dio(baseOpts); // No interceptors — avoids infinite 401 loop

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (!_publicAuthPaths.contains(options.path)) {
          final token = _cachedAccessToken ?? await _storage.read(key: 'access_token');
          if (token != null) {
            _cachedAccessToken = token;
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        if (AppConfig.isDev) debugPrint('[API] ${options.method} ${options.path}');
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (AppConfig.isDev) {
          debugPrint('[API] Error ${error.response?.statusCode}: ${error.requestOptions.path}');
        }
        final errPath = error.requestOptions.path;
        if (error.response?.statusCode == 401 &&
            !_isRefreshing &&
            !_publicAuthPaths.contains(errPath)) {
          final refreshed = await _refreshToken();
          if (refreshed) {
            final opts = error.requestOptions;
            opts.headers['Authorization'] = 'Bearer $_cachedAccessToken';
            try {
              final response = await _dio.fetch(opts);
              return handler.resolve(response);
            } catch (e) {
              return handler.next(error);
            }
          }
        }
        return handler.next(error);
      },
    ));
  }

  /// Retry wrapper for transient errors (5xx / timeout).
  // ignore: unused_element
  Future<Response> _retryRequest(Future<Response> Function() request) async {
    int attempts = 0;
    while (true) {
      try {
        return await request();
      } on DioException catch (e) {
        attempts++;
        final isRetryable = (e.response?.statusCode ?? 0) >= 500 ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout;
        if (!isRetryable || attempts >= AppConfig.maxRetries) {
          throw ErrorHandler.handle(e);
        }
        await Future.delayed(AppConfig.retryDelay * attempts);
      } catch (e) {
        throw ErrorHandler.handle(e);
      }
    }
  }

  Future<bool> _refreshToken() async {
    if (_isRefreshing) return false;
    _isRefreshing = true;
    try {
      final refreshToken = _cachedRefreshToken ?? await _storage.read(key: 'refresh_token');
      if (refreshToken == null) return false;

      final response = await _refreshDio.post('/auth/refresh', data: {
        'refreshToken': refreshToken,
      });

      if (response.statusCode == 200) {
        final newAccess = response.data['data']['accessToken'] as String;
        final newRefresh = response.data['data']['refreshToken'] as String;
        _cachedAccessToken = newAccess;
        _cachedRefreshToken = newRefresh;
        _storage.write(key: 'access_token', value: newAccess);
        _storage.write(key: 'refresh_token', value: newRefresh);
        return true;
      }
    } catch (_) {
      _cachedAccessToken = null;
      _cachedRefreshToken = null;
      await Future.wait([
        _storage.delete(key: 'access_token'),
        _storage.delete(key: 'refresh_token'),
      ]);
    } finally {
      _isRefreshing = false;
    }
    return false;
  }

  // ── Auth ──
  Future<Response> login(String email, String password) async {
    return _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
  }

  Future<Response> register({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    return _dio.post('/auth/register', data: {
      'email': email,
      'password': password,
      'username': username,
      'displayName': displayName,
    });
  }

  Future<Response> socialAuth({
    required String provider,
    required String providerId,
    String? email,
    String? displayName,
    String? avatarUrl,
  }) async {
    return _dio.post('/auth/social', data: {
      'provider': provider,
      'providerId': providerId,
      'email': ?email,
      'displayName': ?displayName,
      'avatarUrl': ?avatarUrl,
    });
  }

  Future<Response> sendVerificationCode(String email) async {
    return _dio.post('/auth/send-code', data: {'email': email});
  }

  Future<Response> verifyCode(String email, String code) async {
    return _dio.post('/auth/verify-code', data: {
      'email': email,
      'code': code,
    });
  }

  Future<Response> requestPasswordReset(String email) async {
    return _dio.post('/auth/password/reset-request', data: {'email': email});
  }

  Future<Response> changePassword(String currentPassword, String newPassword) async {
    return _dio.post('/auth/password/change', data: {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  Future<Response> resetPassword(String email, String code, String newPassword) async {
    return _dio.post('/auth/password/reset', data: {
      'email': email,
      'code': code,
      'newPassword': newPassword,
    });
  }

  // ── User ──
  Future<Response> getCurrentUser() async {
    return _dio.get('/auth/me');
  }

  Future<Response> updateProfile(Map<String, dynamic> data) async {
    return _dio.put('/users/profile', data: data);
  }

  Future<Response> updateAvatarConfig(String avatarConfig) async {
    return _dio.put('/users/profile/avatar-config', data: {
      'avatarConfig': avatarConfig,
    });
  }

  Future<Response> updateAvatarUrl(String avatarUrl) async {
    return _dio.put('/users/profile/avatar', data: {
      'avatarUrl': avatarUrl,
    });
  }

  Future<Response> getUserProfile(String userId) async {
    return _dio.get('/users/profile/$userId');
  }

  // ── Privacy & Notification Settings ──
  Future<Response> getPrivacySettings() async {
    return _dio.get('/users/privacy');
  }

  Future<Response> updatePrivacySettings(Map<String, dynamic> data) async {
    return _dio.put('/users/privacy', data: data);
  }

  Future<Response> getNotificationPreferences() async {
    return _dio.get('/users/notifications/preferences');
  }

  Future<Response> updateNotificationPreferences(Map<String, dynamic> data) async {
    return _dio.put('/users/notifications/preferences', data: data);
  }

  // ── Stories ──
  Future<Response> getStories() async {
    return _dio.get('/stories/feed');
  }

  Future<Response> getMyStories() async {
    return _dio.get('/stories/me');
  }

  Future<Response> createStory(Map<String, dynamic> data) async {
    return _dio.post('/stories', data: data);
  }

  Future<Response> viewStory(String storyId) async {
    return _dio.post('/stories/$storyId/view');
  }

  Future<Response> replyToStory(String storyId, Map<String, dynamic> data) async {
    return _dio.post('/stories/$storyId/reply', data: data);
  }

  Future<Response> deleteStory(String storyId) async {
    return _dio.delete('/stories/$storyId');
  }

  Future<Response> updateStorySettings(String storyId, Map<String, dynamic> data) async {
    return _dio.put('/stories/$storyId/settings', data: data);
  }

  Future<Response> getStoryViewers(String storyId) async {
    return _dio.get('/stories/$storyId/viewers');
  }

  Future<Response> reactToStory(String storyId, String emoji) async {
    return _dio.post('/stories/$storyId/react', data: {'emoji': emoji});
  }

  // ── Highlights ──
  Future<Response> getHighlights(String userId) async {
    return _dio.get('/users/$userId/highlights');
  }

  Future<Response> createHighlight(Map<String, dynamic> data) async {
    return _dio.post('/highlights', data: data);
  }

  Future<Response> deleteHighlight(String highlightId) async {
    return _dio.delete('/highlights/$highlightId');
  }

  // ── Snaps ──
  Future<Response> sendSnap({
    required List<String> recipientIds,
    required String mediaUrl,
    required String mediaType,
    int? viewDuration,
  }) async {
    return _dio.post('/snaps', data: {
      'recipientIds': recipientIds,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'viewDuration': viewDuration ?? 5,
    });
  }

  Future<Response> getReceivedSnaps() async {
    return _dio.get('/snaps/received');
  }

  /// Open a snap and get its media data
  Future<Response> openSnap(String snapId) async {
    return _dio.post('/snaps/$snapId/open');
  }

  // ── Saved Snaps ──
  Future<Response> getSavedSnaps({int limit = 20, int offset = 0}) async {
    return _dio.get('/snaps/saved', queryParameters: {
      'limit': limit,
      'offset': offset,
    });
  }

  Future<Response> saveSnap(String snapId) async {
    return _dio.post('/snaps/$snapId/save');
  }

  Future<Response> unsaveSnap(String snapId) async {
    return _dio.delete('/snaps/$snapId/save');
  }

  Future<Response> isSnapSaved(String snapId) async {
    return _dio.get('/snaps/$snapId/saved');
  }

  // ── Chat ──
  Future<Response> getChats() async {
    return _dio.get('/chats');
  }

  Future<Response> getChatMessages(String chatId, {int? limit, String? before, String? after}) async {
    return _dio.get('/chats/$chatId/messages', queryParameters: {
      'limit': ?limit,
      'before': ?before,
      'after': ?after,
    });
  }

  Future<Response> markAsRead(String chatId, String messageId) async {
    return _dio.post('/chats/$chatId/read', data: {
      'messageId': messageId,
    });
  }

  Future<Response> markMessagesDelivered(String chatId, List<String> messageIds) async {
    return _dio.post('/chats/$chatId/messages/delivered', data: {
      'messageIds': messageIds,
    });
  }

  Future<Response> sendMessage({
    required String chatId,
    required String content,
    String type = 'TEXT',
    String? replyToId,
    String? mediaUrl,
    int? duration,
  }) async {
    return _dio.post('/chats/$chatId/messages', data: {
      'content': content,
      'type': type,
      'replyToId': ?replyToId,
      'mediaUrl': ?mediaUrl,
      'duration': ?duration,
    });
  }

  Future<Response> createChat({
    required List<String> memberIds,
    String? name,
    String? imageUrl,
  }) async {
    return _dio.post('/chats', data: {
      'memberIds': memberIds,
      'name': ?name,
      'imageUrl': ?imageUrl,
    });
  }

  Future<Response> muteChat(String chatId) async {
    return _dio.post('/chats/$chatId/mute');
  }

  Future<Response> leaveChat(String chatId) async {
    return _dio.post('/chats/$chatId/leave');
  }

  Future<Response> deleteChat(String chatId) async {
    return _dio.delete('/chats/$chatId');
  }

  Future<Response> updateChat(String chatId, {
    bool? isDisappearing,
    int? disappearAfter,
    bool clearDisappearAfter = false,
  }) async {
    final data = <String, dynamic>{};
    if (isDisappearing != null) data['isDisappearing'] = isDisappearing;
    // Send disappearAfter explicitly (including null to clear it)
    if (disappearAfter != null) {
      data['disappearAfter'] = disappearAfter;
    } else if (clearDisappearAfter) {
      data['disappearAfter'] = null;
    }
    return _dio.put('/chats/$chatId', data: data);
  }

  // ── Social / Friends ──
  Future<Response> getFriends() async {
    return _dio.get('/social/friends');
  }

  Future<Response> getFriendRequests() async {
    return _dio.get('/social/friends/requests/pending');
  }

  Future<Response> getFriendSuggestions() async {
    return _dio.get('/social/friends/suggestions');
  }

  Future<Response> sendFriendRequest(String userId) async {
    return _dio.post('/social/friends/request/$userId');
  }

  Future<Response> acceptFriendRequest(String requestId) async {
    return _dio.post('/social/friends/accept/$requestId');
  }

  Future<Response> declineFriendRequest(String requestId) async {
    return _dio.post('/social/friends/decline/$requestId');
  }

  Future<Response> removeFriend(String friendId) async {
    return _dio.delete('/social/friends/$friendId');
  }

  Future<Response> blockUser(String userId) async {
    return _dio.post('/social/block/$userId');
  }

  Future<Response> unblockUser(String userId) async {
    return _dio.delete('/social/block/$userId');
  }

  Future<Response> updateFriend(String friendId, Map<String, dynamic> data) async {
    return _dio.put('/social/friends/$friendId/level', data: data);
  }

  Future<Response> getStreaks() async {
    return _dio.get('/snaps/streaks');
  }

  Future<Response> searchUsers(String query) async {
    return _dio.get('/users/search', queryParameters: {'q': query});
  }

  Future<Response> getOrCreateDirectChat(String userId) async {
    return _dio.post('/chats/direct/$userId');
  }

  // ── Discover ──
  Future<Response> getDiscoverFeed() async {
    // Backend has separate endpoints, call events as default feed
    return _dio.get('/discover/events');
  }

  Future<Response> getEvents({String? category, double? lat, double? lng}) async {
    return _dio.get('/discover/events', queryParameters: {
      'category': ?category,
      'lat': ?lat,
      'lng': ?lng,
    });
  }

  Future<Response> getEventDetail(String eventId) async {
    return _dio.get('/events/$eventId');
  }

  Future<Response> attendEvent(String eventId) async {
    return _dio.post('/events/$eventId/rsvp');
  }

  Future<Response> cancelAttendance(String eventId) async {
    return _dio.delete('/events/$eventId/rsvp');
  }

  Future<Response> getNearbyUsers({required double lat, required double lng}) async {
    return _dio.get('/discover/nearby', queryParameters: {'lat': lat, 'lng': lng});
  }

  Future<Response> updateUserLocation({required double lat, required double lng}) async {
    return _dio.put('/users/location', data: {'latitude': lat, 'longitude': lng});
  }

  Future<Response> getFriendLocations() async {
    return _dio.get('/users/friend-locations');
  }

  Future<Response> getMatches() async {
    return _dio.get('/discover/matches');
  }

  Future<Response> searchDiscover(String query) async {
    return _dio.get('/discover/search', queryParameters: {'q': query});
  }

  // ── Media Upload ──
  Future<Response> uploadMedia(String filePath) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    return _dio.post(
      '/media/upload',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
  }

  // ── Message Reactions ──
  Future<Response> reactToMessage(String chatId, String messageId, String emoji) {
    return _dio.post('/chats/$chatId/messages/$messageId/react', data: {'emoji': emoji});
  }

  // ── Notifications ──
  Future<Response> getNotifications({int? limit, int? offset}) async {
    return _dio.get('/notifications', queryParameters: {
      'limit': ?limit,
      'offset': ?offset,
    });
  }

  /// Register device token for push notifications (FCM via AWS SNS).
  Future<Response> registerDeviceToken(String token, String platform) async {
    return _dio.post('/notifications/device', data: {
      'token': token,
      'platform': platform,
    });
  }

  /// Unregister device from push notifications.
  Future<Response> unregisterDeviceToken() async {
    return _dio.delete('/notifications/device');
  }

  Future<Response> markNotificationAsRead(String notificationId) async {
    return _dio.post('/notifications/$notificationId/read');
  }

  Future<Response> markAllNotificationsAsRead() async {
    return _dio.post('/notifications/read-all');
  }

  Future<Response> deleteNotification(String notificationId) async {
    return _dio.delete('/notifications/$notificationId');
  }

  Future<Response> clearAllNotifications() async {
    return _dio.delete('/notifications');
  }

  // ── AI Chat ──
  Future<Response> chatWithAI(String message) async {
    return _dio.post('/ai/chat', data: {'message': message});
  }

  // ── Memories ──
  Future<Response> getMemories({int limit = 50, int offset = 0}) async {
    return _dio.get('/memories', queryParameters: {
      'limit': limit,
      'offset': offset,
    });
  }

  Future<Response> getMemoryAlbums() async {
    return _dio.get('/memories/albums');
  }

  Future<Response> saveToMemories({
    required String mediaUrl,
    required String mediaType,
    String? thumbnailUrl,
    String? caption,
    String? location,
    double? latitude,
    double? longitude,
    String? originalSnapId,
    String? originalStoryId,
    String? albumId,
  }) async {
    return _dio.post('/memories', data: {
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'thumbnailUrl': ?thumbnailUrl,
      'caption': ?caption,
      'location': ?location,
      'latitude': ?latitude,
      'longitude': ?longitude,
      'originalSnapId': ?originalSnapId,
      'originalStoryId': ?originalStoryId,
      'albumId': ?albumId,
    });
  }

  Future<Response> createMemoryAlbum({
    required String name,
    String? coverUrl,
    bool? isPrivate,
  }) async {
    return _dio.post('/memories/albums', data: {
      'name': name,
      'coverUrl': ?coverUrl,
      'isPrivate': ?isPrivate,
    });
  }

  Future<Response> deleteMemory(String id) async {
    return _dio.delete('/memories/$id');
  }

  Future<Response> updateMemory(String id, {String? caption, String? albumId}) async {
    return _dio.patch('/memories/$id', data: {
      'caption': ?caption,
      'albumId': ?albumId,
    });
  }

  Future<Response> reshareMemory(String id) async {
    return _dio.post('/memories/$id/reshare');
  }

  // ── Transport ──
  Future<Response> getTubeStatus() async {
    return _dio.get('/transport/tube-status');
  }

  Future<Response> getRouteOptions(Map<String, dynamic> params) async {
    return _dio.get('/transport/route', queryParameters: params);
  }

  Future<Response> getNearbyStops(Map<String, dynamic> params) async {
    return _dio.get('/transport/nearby-stops', queryParameters: params);
  }

  // ── Safety Walk ──
  Future<Response> findSafetyCompanions(Map<String, dynamic> data) async {
    return _dio.post('/safety-walk/find-companions', data: data);
  }

  Future<Response> requestSafetyWalk(Map<String, dynamic> data) async {
    return _dio.post('/safety-walk/request', data: data);
  }

  Future<Response> acceptSafetyWalk(String walkId) async {
    return _dio.post('/safety-walk/$walkId/accept');
  }

  Future<Response> declineSafetyWalk(String walkId) async {
    return _dio.post('/safety-walk/$walkId/decline');
  }

  Future<Response> startSafetyWalk(String walkId) async {
    return _dio.post('/safety-walk/$walkId/start');
  }

  Future<Response> updateWalkLocation(String walkId, Map<String, dynamic> data) async {
    return _dio.post('/safety-walk/$walkId/location', data: data);
  }

  Future<Response> triggerSOS(String walkId) async {
    return _dio.post('/safety-walk/$walkId/sos');
  }

  Future<Response> completeSafetyWalk(String walkId) async {
    return _dio.post('/safety-walk/$walkId/complete');
  }

  Future<Response> rateSafetyWalkCompanion(String walkId, Map<String, dynamic> data) async {
    return _dio.post('/safety-walk/$walkId/rate', data: data);
  }

  Future<Response> getActiveWalk() async {
    return _dio.get('/safety-walk/active');
  }

  Future<Response> getSafetyScore() async {
    return _dio.get('/safety-walk/score');
  }

  Future<Response> getWalkHistory({int limit = 20, int offset = 0}) async {
    return _dio.get('/safety-walk/history', queryParameters: {
      'limit': limit,
      'offset': offset,
    });
  }

  Future<Response> cancelSafetyWalk(String walkId) async {
    return _dio.delete('/safety-walk/$walkId');
  }

  // ── University Verification ──
  Future<Response> verifyUniversityEmail(String email) async {
    return _dio.post('/auth/verify-university', data: {
      'universityEmail': email,
    });
  }

  Future<Response> completeUniversityVerification(String code) async {
    return _dio.post('/auth/verify-university/complete', data: {
      'code': code,
    });
  }

  // ── Token Management ──
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    _cachedAccessToken = accessToken;
    _cachedRefreshToken = refreshToken;
    await Future.wait([
      _storage.write(key: 'access_token', value: accessToken),
      _storage.write(key: 'refresh_token', value: refreshToken),
    ]);
  }

  Future<void> clearTokens() async {
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    await Future.wait([
      _storage.delete(key: 'access_token'),
      _storage.delete(key: 'refresh_token'),
    ]);
  }

  Future<bool> hasToken() async {
    if (_cachedAccessToken != null) return true;
    final token = await _storage.read(key: 'access_token');
    if (token != null) _cachedAccessToken = token;
    return token != null;
  }

  // ── My Eyes Only Vault ──

  Future<Response> getVaultStatus() async {
    return _dio.get('/memories/my-eyes-only/status');
  }

  Future<Response> setupVaultPin(String pin) async {
    return _dio.post('/memories/my-eyes-only/setup', data: {'pin': pin});
  }

  Future<Response> verifyVaultPin(String pin) async {
    return _dio.post('/memories/my-eyes-only/verify', data: {'pin': pin});
  }

  Future<Response> changeVaultPin(String currentPin, String newPin) async {
    return _dio.post('/memories/my-eyes-only/change-pin', data: {
      'currentPin': currentPin,
      'newPin': newPin,
    });
  }

  Future<Response> getMyEyesOnlyMemories({int limit = 50, int offset = 0}) async {
    return _dio.get('/memories/my-eyes-only', 
      queryParameters: {'limit': limit, 'offset': offset},
      options: Options(headers: {'x-vault-token': _vaultToken ?? ''}),
    );
  }

  Future<Response> moveToVault(String memoryId) async {
    return _dio.post('/memories/$memoryId/move-to-vault');
  }

  Future<Response> moveFromVault(String memoryId) async {
    return _dio.post('/memories/$memoryId/move-from-vault',
      options: Options(headers: {'x-vault-token': _vaultToken ?? ''}),
    );
  }

  // Vault token management
  String? _vaultToken;
  void setVaultToken(String? token) => _vaultToken = token;
}
