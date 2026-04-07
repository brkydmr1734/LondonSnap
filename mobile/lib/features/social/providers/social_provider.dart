import 'dart:async';
import 'package:flutter/material.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/core/errors/app_exceptions.dart';
import 'package:londonsnaps/core/errors/error_handler.dart';
import 'package:londonsnaps/features/chat/providers/chat_provider.dart';
import 'package:londonsnaps/features/social/models/social_models.dart';
import 'package:londonsnaps/shared/models/user.dart';

class SocialProvider extends ChangeNotifier {
  static final SocialProvider _instance = SocialProvider._internal();
  factory SocialProvider() => _instance;
  SocialProvider._internal();

  final ApiService _api = ApiService();
  ChatProvider? _chatProvider;

  void setChatProvider(ChatProvider chatProvider) {
    _chatProvider = chatProvider;
  }

  List<SocialFriend> _friends = [];
  List<FriendRequest> _friendRequests = [];
  List<FriendSuggestion> _suggestions = [];
  List<Streak> _streaks = [];
  UserProfile? _selectedProfile;
  List<FriendUser> _searchResults = [];
  bool _isLoading = false;
  String? _error;
  Timer? _searchDebounce;

  /// IDs of users we already sent a friend request to (this session)
  final Set<String> _sentRequestIds = {};

  List<SocialFriend> get friends => _friends;
  List<FriendRequest> get friendRequests => _friendRequests;
  List<FriendSuggestion> get suggestions => _suggestions;
  List<Streak> get streaks => _streaks;
  UserProfile? get selectedProfile => _selectedProfile;
  List<FriendUser> get searchResults => _searchResults;
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<SocialFriend> get bestFriends => _friends.where((f) => f.isBestFriend).toList();
  List<Streak> get atRiskStreaks => _streaks.where((s) => s.hoursRemaining <= 4 && s.isActive).toList();
  Set<String> get sentRequestIds => _sentRequestIds;
  bool hasSentRequest(String userId) => _sentRequestIds.contains(userId);

  Future<void> loadFriends() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await _api.getFriends();
      final friendsList = response.data['data']['friends'] as List? ?? [];
      _friends = friendsList.map((f) {
        final map = f as Map<String, dynamic>;
        // Backend returns flat: {id, username, displayName, level, friendSince, emoji, emojiLabel}
        // Flutter expects nested: {id, user: {...}, isBestFriend, isCloseFriend, friendsSince, emoji, emojiLabel}
        return SocialFriend.fromJson({
          'id': map['id'],
          'user': {
            'id': map['id'],
            'username': map['username'],
            'displayName': map['displayName'],
            'avatarUrl': map['avatarUrl'],
            'isVerified': map['isVerified'] ?? false,
            'isOnline': map['isOnline'] ?? false,
            'lastSeenAt': map['lastSeenAt'],
          },
          'isBestFriend': map['level'] == 'BEST',
          'isCloseFriend': map['level'] == 'CLOSE' || map['level'] == 'BEST',
          'friendsSince': map['friendSince'] ?? map['createdAt'] ?? DateTime.now().toIso8601String(),
          'emoji': map['emoji'],
          'emojiLabel': map['emojiLabel'],
        });
      }).toList();
    } catch (e) {
      _error = _handleError(e);
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadFriendRequests() async {
    _error = null;
    try {
      final response = await _api.getFriendRequests();
      final requestsList = response.data['data']['requests'] as List? ?? [];
      _friendRequests = requestsList.map((r) {
        final map = r as Map<String, dynamic>;
        // Backend returns: {id, senderId, receiverId, sender: {...}, createdAt}
        // Flutter expects: {id, fromUser: {...}, toUser: {...}, mutualFriends, createdAt}
        return FriendRequest.fromJson({
          'id': map['id'],
          'fromUser': map['sender'] ?? {'id': map['senderId'], 'username': '', 'displayName': 'Unknown'},
          'toUser': {'id': map['receiverId'] ?? '', 'username': '', 'displayName': 'You'},
          'mutualFriends': map['mutualFriends'] ?? 0,
          'createdAt': map['createdAt'],
        });
      }).toList();
      notifyListeners();
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  Future<void> loadSuggestions() async {
    _error = null;
    try {
      final response = await _api.getFriendSuggestions();
      final suggestionsList = response.data['data']['suggestions'] as List? ?? [];
      _suggestions = suggestionsList.map((s) {
        final map = s as Map<String, dynamic>;
        // Backend returns flat: {id, username, displayName, avatarUrl, isVerified, university: {shortName}}
        // Flutter expects: {id, user: {...}, reason, mutualFriends, university}
        return FriendSuggestion.fromJson({
          'id': map['id'],
          'user': {
            'id': map['id'],
            'username': map['username'],
            'displayName': map['displayName'],
            'avatarUrl': map['avatarUrl'],
            'isVerified': map['isVerified'] ?? false,
          },
          'reason': map['isUniversityStudent'] == true ? 'sameUniversity' : 'mutualFriends',
          'mutualFriends': map['mutualFriends'] ?? 0,
          'university': map['university']?['shortName'],
        });
      }).toList();
      notifyListeners();
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  Future<void> loadStreaks() async {
    _error = null;
    try {
      final response = await _api.getStreaks();
      final streaksList = response.data['data']['streaks'] as List? ?? [];
      _streaks = streaksList.map((s) => Streak.fromJson(s as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  Future<void> loadProfile(String userId) async {
    _isLoading = true;
    _error = null;
    _selectedProfile = null;
    notifyListeners();
    try {
      debugPrint('[SocialProvider] Loading profile for userId: $userId');
      final response = await _api.getUserProfile(userId);
      debugPrint('[SocialProvider] Response status: ${response.statusCode}');

      // Safely extract profile data from response
      final responseData = response.data;
      if (responseData is! Map) {
        debugPrint('[SocialProvider] Response data is not a Map: $responseData');
        _error = 'Invalid response from server';
        _isLoading = false;
        notifyListeners();
        return;
      }

      dynamic data = responseData['data'];
      if (data is! Map) {
        debugPrint('[SocialProvider] response.data["data"] is not a Map: $data');
        _error = 'Invalid profile data';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Backend may wrap in "user" key or return flat
      final profileData = data.containsKey('user') && data['user'] is Map
          ? Map<String, dynamic>.from(data['user'] as Map)
          : Map<String, dynamic>.from(data);

      debugPrint('[SocialProvider] profileData keys: ${profileData.keys.toList()}');

      try {
        _selectedProfile = UserProfile.fromJson(profileData);
        debugPrint('[SocialProvider] Profile parsed OK: ${_selectedProfile?.displayName}');
      } catch (parseError, stack) {
        debugPrint('[SocialProvider] Failed to parse UserProfile: $parseError');
        debugPrint('[SocialProvider] Stack: $stack');
        debugPrint('[SocialProvider] Profile data: $profileData');
        _error = 'Failed to load profile data';
      }
    } catch (e, stack) {
      debugPrint('[SocialProvider] loadProfile error: $e');
      debugPrint('[SocialProvider] Stack: $stack');
      _error = _handleError(e);
      debugPrint('[SocialProvider] Error message set to: $_error');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> sendFriendRequest(String userId) async {
    try {
      await _api.sendFriendRequest(userId);
      _sentRequestIds.add(userId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
      return false;
    }
  }

  Future<void> acceptFriendRequest(String requestId) async {
    try {
      await _api.acceptFriendRequest(requestId);
      _friendRequests.removeWhere((r) => r.id == requestId);
      await loadFriends();
      // Refresh chats so the new direct chat appears immediately
      _chatProvider?.loadChats();
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  Future<void> declineFriendRequest(String requestId) async {
    try {
      await _api.declineFriendRequest(requestId);
      _friendRequests.removeWhere((r) => r.id == requestId);
      notifyListeners();
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  Future<void> removeFriend(String friendId) async {
    try {
      await _api.removeFriend(friendId);
      _friends.removeWhere((f) => f.id == friendId);
      notifyListeners();
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  Future<void> blockUser(String userId) async {
    try {
      await _api.blockUser(userId);
      notifyListeners();
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  Future<void> unblockUser(String userId) async {
    try {
      await _api.unblockUser(userId);
      notifyListeners();
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  Future<void> updateFriend(String friendId, {bool? isBestFriend, bool? isCloseFriend}) async {
    try {
      String level = 'NORMAL';
      if (isBestFriend == true) {
        level = 'BEST';
      } else if (isCloseFriend == true) {
        level = 'CLOSE';
      }
      await _api.updateFriend(friendId, {'level': level});
      await loadFriends();
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  void searchUsers(String query) {
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final response = await _api.searchUsers(query);
        final usersList = response.data['data']['users'] as List? ?? response.data['data'] as List? ?? [];
        _searchResults = usersList.map((u) => FriendUser.fromJson(u as Map<String, dynamic>)).toList();
        notifyListeners();
      } catch (e) {
        _error = _handleError(e);
        notifyListeners();
      }
    });
  }

  String _handleError(dynamic e) {
    final ex = e is AppException ? e : ErrorHandler.handle(e);
    return ex.message;
  }
}
