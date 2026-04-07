class User {
  final String id;
  final String email;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarConfig;
  final String? bio;
  final DateTime? birthday;
  final String? gender;
  final bool isVerified;
  final bool isUniversityStudent;
  final String? universityId;
  final University? university;
  final String? course;
  final int? graduationYear;
  final int snapScore;
  final DateTime createdAt;

  User({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.avatarConfig,
    this.bio,
    this.birthday,
    this.gender,
    this.isVerified = false,
    this.isUniversityStudent = false,
    this.universityId,
    this.university,
    this.course,
    this.graduationYear,
    this.snapScore = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      email: json['email'],
      username: json['username'],
      displayName: json['displayName'],
      avatarUrl: json['avatarUrl'],
      avatarConfig: json['avatarConfig'],
      bio: json['bio'],
      birthday: json['birthday'] != null ? DateTime.parse(json['birthday']) : null,
      gender: json['gender'],
      isVerified: json['isVerified'] ?? false,
      isUniversityStudent: json['isUniversityStudent'] ?? false,
      universityId: json['universityId'],
      university: json['university'] != null
          ? University.fromJson(json['university'])
          : null,
      course: json['course'],
      graduationYear: json['graduationYear'],
      snapScore: json['snapScore'] ?? 0,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'avatarConfig': avatarConfig,
      'bio': bio,
      'birthday': birthday?.toIso8601String(),
      'gender': gender,
      'isVerified': isVerified,
      'isUniversityStudent': isUniversityStudent,
      'universityId': universityId,
      'course': course,
      'graduationYear': graduationYear,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class University {
  final String id;
  final String name;
  final String shortName;
  final String? domain;
  final String? logoUrl;

  University({
    required this.id,
    required this.name,
    required this.shortName,
    this.domain,
    this.logoUrl,
  });

  factory University.fromJson(Map<String, dynamic> json) {
    return University(
      id: json['id'],
      name: json['name'],
      shortName: json['shortName'],
      domain: json['domain'],
      logoUrl: json['logoUrl'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'shortName': shortName,
    'domain': domain, 'logoUrl': logoUrl,
  };
}

class BasicFriend {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  BasicFriend({required this.id, required this.username, required this.displayName, this.avatarUrl});

  factory BasicFriend.fromJson(Map<String, dynamic> json) {
    return BasicFriend(
      id: json['id'], username: json['username'],
      displayName: json['displayName'], avatarUrl: json['avatarUrl'],
    );
  }
}

class Friend {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final bool isVerified;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final Streak? streak;

  Friend({
    required this.id, required this.username, required this.displayName,
    this.avatarUrl, this.isVerified = false, this.isOnline = false,
    this.lastSeenAt, this.streak,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      id: json['id'], username: json['username'],
      displayName: json['displayName'], avatarUrl: json['avatarUrl'],
      isVerified: json['isVerified'] ?? false,
      isOnline: json['isOnline'] ?? false,
      lastSeenAt: json['lastSeenAt'] != null ? DateTime.parse(json['lastSeenAt']) : null,
      streak: json['streak'] != null ? Streak.fromJson(json['streak']) : null,
    );
  }
}

class Streak {
  final String id;
  final int count;
  final DateTime lastInteraction;
  final DateTime expiresAt;
  final bool isActive;
  final int longestStreak;

  Streak({
    required this.id, required this.count, required this.lastInteraction,
    required this.expiresAt, this.isActive = true, required this.longestStreak,
  });

  factory Streak.fromJson(Map<String, dynamic> json) {
    return Streak(
      id: json['id'], count: json['count'],
      lastInteraction: DateTime.parse(json['lastInteractionAt']),
      expiresAt: DateTime.parse(json['expiresAt']),
      isActive: json['isActive'] ?? true,
      longestStreak: json['longestStreak'] ?? json['count'],
    );
  }

  int get hoursRemaining {
    final diff = expiresAt.difference(DateTime.now());
    return diff.inHours > 0 ? diff.inHours : 0;
  }

  String get emoji {
    if (count < 7) return '🔥';
    if (count < 30) return '💥';
    if (count < 100) return '⚡️';
    if (count < 365) return '💯';
    return '🌟';
  }
}

enum SnapStatus { sent, delivered, opened, screenshot, expired }
enum EventStatus { upcoming, ongoing, ended, cancelled }
enum NotificationType { friendRequest, snap, message, storyReply, eventInvite, streak }

class LondonArea {
  final String id;
  final String name;
  final String? imageUrl;
  final int activeUsers;

  LondonArea({required this.id, required this.name, this.imageUrl, this.activeUsers = 0});

  factory LondonArea.fromJson(Map<String, dynamic> json) {
    return LondonArea(
      id: json['id'], name: json['name'],
      imageUrl: json['imageUrl'], activeUsers: json['activeUsers'] ?? 0,
    );
  }
}

class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final String? imageUrl;
  final String? actionId;
  final bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id, required this.type, required this.title,
    required this.body, this.imageUrl, this.actionId,
    this.isRead = false, required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'],
      type: NotificationType.values.firstWhere(
        (e) => e.name == (json['type'] as String).toLowerCase(),
        orElse: () => NotificationType.message,
      ),
      title: json['title'], body: json['body'],
      imageUrl: json['imageUrl'], actionId: json['actionId'],
      isRead: json['isRead'] ?? false,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}
