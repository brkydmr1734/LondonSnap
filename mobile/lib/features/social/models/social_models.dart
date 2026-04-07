import 'package:londonsnaps/shared/models/user.dart';

enum FriendshipStatus {
  none, pending, accepted, blocked;
  factory FriendshipStatus.fromString(String? s) {
    if (s == null) return none;
    return values.firstWhere((e) => e.name == s.toLowerCase(), orElse: () => none);
  }
}

enum SuggestionReason {
  mutualFriends, sameUniversity, sameArea, sameInterests;
  String get displayText {
    switch (this) {
      case mutualFriends: return 'Mutual Friends';
      case sameUniversity: return 'Same University';
      case sameArea: return 'Same Area';
      case sameInterests: return 'Similar Interests';
    }
  }
  factory SuggestionReason.fromString(String s) =>
      values.firstWhere((e) => e.name == s, orElse: () => mutualFriends);
}

class FriendUser {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarConfig;
  final bool isVerified;
  final bool isOnline;
  final DateTime? lastSeenAt;

  FriendUser({required this.id, required this.username, required this.displayName,
    this.avatarUrl, this.avatarConfig, this.isVerified = false, this.isOnline = false, this.lastSeenAt});

  factory FriendUser.fromJson(Map<String, dynamic> json) => FriendUser(
    id: json['id'], username: json['username'], displayName: json['displayName'],
    avatarUrl: json['avatarUrl'], avatarConfig: json['avatarConfig'],
    isVerified: json['isVerified'] ?? false,
    isOnline: json['isOnline'] ?? false,
    lastSeenAt: json['lastSeenAt'] != null ? DateTime.parse(json['lastSeenAt']) : null,
  );
}

class SocialFriend {
  final String id;
  final FriendUser user;
  final bool isBestFriend;
  final bool isCloseFriend;
  final Streak? streak;
  final DateTime friendsSince;
  final String? emoji;
  final String? emojiLabel;

  SocialFriend({required this.id, required this.user, this.isBestFriend = false,
    this.isCloseFriend = false, this.streak, required this.friendsSince,
    this.emoji, this.emojiLabel});

  factory SocialFriend.fromJson(Map<String, dynamic> json) => SocialFriend(
    id: json['id'], user: FriendUser.fromJson(json['user']),
    isBestFriend: json['isBestFriend'] ?? false,
    isCloseFriend: json['isCloseFriend'] ?? false,
    streak: json['streak'] != null ? Streak.fromJson(json['streak']) : null,
    friendsSince: DateTime.parse(json['friendsSince']),
    emoji: json['emoji'],
    emojiLabel: json['emojiLabel'],
  );
}

class FriendRequest {
  final String id;
  final FriendUser fromUser;
  final FriendUser toUser;
  final int mutualFriends;
  final DateTime createdAt;

  FriendRequest({required this.id, required this.fromUser, required this.toUser,
    this.mutualFriends = 0, required this.createdAt});

  factory FriendRequest.fromJson(Map<String, dynamic> json) => FriendRequest(
    id: json['id'], fromUser: FriendUser.fromJson(json['fromUser']),
    toUser: FriendUser.fromJson(json['toUser']),
    mutualFriends: json['mutualFriends'] ?? 0,
    createdAt: DateTime.parse(json['createdAt']),
  );
}

class FriendSuggestion {
  final String id;
  final FriendUser user;
  final SuggestionReason reason;
  final int mutualFriends;
  final String? university;

  FriendSuggestion({required this.id, required this.user, required this.reason,
    this.mutualFriends = 0, this.university});

  factory FriendSuggestion.fromJson(Map<String, dynamic> json) => FriendSuggestion(
    id: json['id'], user: FriendUser.fromJson(json['user']),
    reason: SuggestionReason.fromString(json['reason'] ?? 'mutualFriends'),
    mutualFriends: json['mutualFriends'] ?? 0, university: json['university'],
  );
}

class ProfileLocation {
  final double latitude;
  final double longitude;
  final String? area;
  final DateTime? updatedAt;

  ProfileLocation({
    required this.latitude,
    required this.longitude,
    this.area,
    this.updatedAt,
  });

  factory ProfileLocation.fromJson(Map<String, dynamic> json) => ProfileLocation(
    latitude: _parseDouble(json['latitude']),
    longitude: _parseDouble(json['longitude']),
    area: json['area'] as String?,
    updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'].toString()) : null,
  );

  static double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }
}

class UserProfile {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarConfig;
  final String? bio;
  final bool isVerified;
  final FriendshipStatus friendshipStatus;
  final bool isBestFriend;
  final bool isCloseFriend;
  final bool isBlocked;
  final int friendsCount;
  final int streakCount;
  final int snapScore;
  final List<FriendUser> mutualFriends;
  final University? university;
  final ProfileLocation? location;

  UserProfile({required this.id, required this.username, required this.displayName,
    this.avatarUrl, this.avatarConfig, this.bio, this.isVerified = false,
    this.friendshipStatus = FriendshipStatus.none,
    this.isBestFriend = false, this.isCloseFriend = false, this.isBlocked = false,
    this.friendsCount = 0, this.streakCount = 0, this.snapScore = 0,
    this.mutualFriends = const [], this.university, this.location});

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] ?? '',
    username: json['username'] ?? '',
    displayName: json['displayName'] ?? json['display_name'] ?? '',
    avatarUrl: json['avatarUrl'] as String?,
    avatarConfig: json['avatarConfig'] as String?,
    bio: json['bio'] as String?,
    isVerified: json['isVerified'] ?? false,
    friendshipStatus: FriendshipStatus.fromString(json['friendshipStatus'] as String?),
    isBestFriend: json['isBestFriend'] ?? false,
    isCloseFriend: json['isCloseFriend'] ?? false,
    isBlocked: json['isBlocked'] ?? false,
    friendsCount: json['friendsCount'] ?? json['friendCount'] ?? 0,
    streakCount: json['streakCount'] ?? json['streak_count'] ?? 0,
    snapScore: json['snapScore'] ?? json['snap_score'] ?? 0,
    mutualFriends: (json['mutualFriends'] as List? ?? [])
        .map((f) => FriendUser.fromJson(f as Map<String, dynamic>)).toList(),
    university: json['university'] != null ? University.fromJson(json['university']) : null,
    location: json['location'] != null ? ProfileLocation.fromJson(json['location']) : null,
  );
}

class SocialCircle {
  final String id;
  final String name;
  final String? description;
  final String? imageUrl;
  final int memberCount;
  final bool isMember;
  final DateTime createdAt;

  SocialCircle({required this.id, required this.name, this.description, this.imageUrl,
    this.memberCount = 0, this.isMember = false, required this.createdAt});

  factory SocialCircle.fromJson(Map<String, dynamic> json) => SocialCircle(
    id: json['id'], name: json['name'], description: json['description'],
    imageUrl: json['imageUrl'], memberCount: json['memberCount'] ?? 0,
    isMember: json['isMember'] ?? false, createdAt: DateTime.parse(json['createdAt']),
  );
}
