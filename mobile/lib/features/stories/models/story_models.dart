enum StoryMediaType {
  image('IMAGE'),
  video('VIDEO');
  final String value;
  const StoryMediaType(this.value);
  factory StoryMediaType.fromString(String s) =>
      values.firstWhere((e) => e.value == s, orElse: () => image);
}

enum StoryPrivacy {
  everyone('EVERYONE', 'Everyone', '🌐'),
  friends('FRIENDS', 'Friends', '👥'),
  closeFriends('CLOSE_FRIENDS', 'Close Friends', '⭐'),
  custom('CUSTOM', 'Custom', '👤');
  final String value;
  final String displayName;
  final String icon;
  const StoryPrivacy(this.value, this.displayName, this.icon);
  factory StoryPrivacy.fromString(String s) =>
      values.firstWhere((e) => e.value == s, orElse: () => friends);
}

enum StickerType {
  emoji, gif, poll, question, countdown, location, mention, link;
  factory StickerType.fromString(String s) =>
      values.firstWhere((e) => e.name == s.toLowerCase(), orElse: () => emoji);
}

enum StoryTextAlignment {
  left, center, right;
  factory StoryTextAlignment.fromString(String s) =>
      values.firstWhere((e) => e.name == s.toLowerCase(), orElse: () => center);
}

class Story {
  final String id;
  final String userId;
  final StoryUser user;
  final String mediaUrl;
  final String? thumbnailUrl;
  final StoryMediaType mediaType;
  final int duration;
  final String? caption;
  final StoryLocation? location;
  final StoryMusic? music;
  final List<StoryMention> mentions;
  final List<StorySticker> stickers;
  final List<StoryTextOverlay> textOverlays;
  final int viewCount;
  final int replyCount;
  final List<StoryViewer> viewers;
  final StoryPrivacy privacy;
  final bool allowReplies;
  final DateTime expiresAt;
  final DateTime createdAt;

  Story({
    required this.id, required this.userId, required this.user,
    required this.mediaUrl, this.thumbnailUrl, required this.mediaType,
    this.duration = 5, this.caption, this.location, this.music,
    this.mentions = const [], this.stickers = const [],
    this.textOverlays = const [], this.viewCount = 0, this.replyCount = 0,
    this.viewers = const [], this.privacy = StoryPrivacy.friends,
    this.allowReplies = true, required this.expiresAt, required this.createdAt,
  });

  bool get isExpired => expiresAt.isBefore(DateTime.now());
  Duration get remainingTime {
    final diff = expiresAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }
  String get formattedTime {
    final interval = DateTime.now().difference(createdAt);
    if (interval.inSeconds < 60) return 'Just now';
    if (interval.inMinutes < 60) return '${interval.inMinutes}m';
    return '${interval.inHours}h';
  }

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id'], userId: json['userId'],
      user: StoryUser.fromJson(json['user']),
      mediaUrl: json['mediaUrl'], thumbnailUrl: json['thumbnailUrl'],
      mediaType: StoryMediaType.fromString(json['mediaType'] ?? 'IMAGE'),
      duration: json['duration'] ?? 5, caption: json['caption'],
      location: json['location'] != null ? StoryLocation.fromJson(json['location']) : null,
      music: json['music'] != null ? StoryMusic.fromJson(json['music']) : null,
      mentions: (json['mentions'] as List? ?? []).map((m) => StoryMention.fromJson(m)).toList(),
      stickers: (json['stickers'] as List? ?? []).map((s) => StorySticker.fromJson(s)).toList(),
      textOverlays: (json['textOverlays'] as List? ?? []).map((t) => StoryTextOverlay.fromJson(t)).toList(),
      viewCount: json['viewCount'] ?? 0, replyCount: json['replyCount'] ?? 0,
      viewers: (json['viewers'] as List? ?? []).map((v) => StoryViewer.fromJson(v)).toList(),
      privacy: StoryPrivacy.fromString(json['privacy'] ?? 'FRIENDS'),
      allowReplies: json['allowReplies'] ?? true,
      expiresAt: DateTime.parse(json['expiresAt']),
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class StoryUser {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarConfig;
  final bool isVerified;

  StoryUser({required this.id, required this.username, required this.displayName,
    this.avatarUrl, this.avatarConfig, this.isVerified = false});

  factory StoryUser.fromJson(Map<String, dynamic> json) {
    return StoryUser(
      id: json['id'], username: json['username'],
      displayName: json['displayName'], avatarUrl: json['avatarUrl'],
      avatarConfig: json['avatarConfig'],
      isVerified: json['isVerified'] ?? false,
    );
  }
}

class StoryViewer {
  final String id;
  final String userId;
  final StoryUser user;
  final DateTime viewedAt;

  StoryViewer({required this.id, required this.userId, required this.user, required this.viewedAt});

  factory StoryViewer.fromJson(Map<String, dynamic> json) {
    return StoryViewer(
      id: json['id'], userId: json['userId'],
      user: StoryUser.fromJson(json['user']),
      viewedAt: DateTime.parse(json['viewedAt']),
    );
  }
}

class StoryLocation {
  final String name;
  final double latitude;
  final double longitude;
  StoryLocation({required this.name, required this.latitude, required this.longitude});
  factory StoryLocation.fromJson(Map<String, dynamic> json) => StoryLocation(
    name: json['name'],
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
  );
}

class StoryMusic {
  final String id;
  final String title;
  final String artist;
  final String? coverUrl;
  StoryMusic({required this.id, required this.title, required this.artist, this.coverUrl});
  factory StoryMusic.fromJson(Map<String, dynamic> json) => StoryMusic(
    id: json['id'], title: json['title'], artist: json['artist'], coverUrl: json['coverUrl'],
  );
}

class StoryMention {
  final String id;
  final String userId;
  final String username;
  final double x;
  final double y;
  StoryMention({required this.id, required this.userId, required this.username,
    required this.x, required this.y});
  factory StoryMention.fromJson(Map<String, dynamic> json) => StoryMention(
    id: json['id'], userId: json['userId'], username: json['username'],
    x: (json['x'] as num?)?.toDouble() ?? 0, y: (json['y'] as num?)?.toDouble() ?? 0,
  );
}

class StorySticker {
  final String id;
  final StickerType type;
  final String? imageUrl;
  final String? emoji;
  final double x, y, scale, rotation;
  StorySticker({required this.id, required this.type, this.imageUrl, this.emoji,
    required this.x, required this.y, this.scale = 1.0, this.rotation = 0});
  factory StorySticker.fromJson(Map<String, dynamic> json) => StorySticker(
    id: json['id'], type: StickerType.fromString(json['type'] ?? 'emoji'),
    imageUrl: json['imageUrl'], emoji: json['emoji'],
    x: (json['x'] as num?)?.toDouble() ?? 0, y: (json['y'] as num?)?.toDouble() ?? 0,
    scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
    rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
  );
}

class StoryTextOverlay {
  final String id;
  final String text;
  final String font;
  final double fontSize;
  final String color;
  final String? backgroundColor;
  final double x, y, rotation;
  final StoryTextAlignment alignment;
  StoryTextOverlay({required this.id, required this.text, required this.font,
    required this.fontSize, required this.color, this.backgroundColor,
    required this.x, required this.y, this.rotation = 0,
    this.alignment = StoryTextAlignment.center});
  factory StoryTextOverlay.fromJson(Map<String, dynamic> json) => StoryTextOverlay(
    id: json['id'], text: json['text'], font: json['font'] ?? 'default',
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? 16,
    color: json['color'] ?? '#FFFFFF', backgroundColor: json['backgroundColor'],
    x: (json['x'] as num?)?.toDouble() ?? 0, y: (json['y'] as num?)?.toDouble() ?? 0,
    rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
    alignment: StoryTextAlignment.fromString(json['alignment'] ?? 'center'),
  );
}

class StoryRing {
  final String id;
  final StoryUser user;
  final List<Story> stories;
  final bool hasUnviewed;
  final DateTime lastStoryAt;
  StoryRing({required this.id, required this.user, required this.stories,
    this.hasUnviewed = false, required this.lastStoryAt});
  Story? get latestStory => stories.isNotEmpty ? stories.last : null;
  factory StoryRing.fromJson(Map<String, dynamic> json) => StoryRing(
    id: json['id'], user: StoryUser.fromJson(json['user']),
    stories: (json['stories'] as List? ?? []).map((s) => Story.fromJson(s)).toList(),
    hasUnviewed: json['hasUnviewed'] ?? false,
    lastStoryAt: DateTime.parse(json['lastStoryAt']),
  );
}

class StoryHighlight {
  final String id;
  final String userId;
  final String title;
  final String? coverUrl;
  final List<Story> stories;
  final DateTime createdAt;
  final DateTime updatedAt;
  StoryHighlight({required this.id, required this.userId, required this.title,
    this.coverUrl, this.stories = const [], required this.createdAt, required this.updatedAt});
  factory StoryHighlight.fromJson(Map<String, dynamic> json) => StoryHighlight(
    id: json['id'], userId: json['userId'], title: json['title'],
    coverUrl: json['coverUrl'],
    stories: (json['stories'] as List? ?? []).map((s) => Story.fromJson(s)).toList(),
    createdAt: DateTime.parse(json['createdAt']), updatedAt: DateTime.parse(json['updatedAt']),
  );
}

class StoryReply {
  final String id;
  final String storyId;
  final String userId;
  final StoryUser user;
  final String? content;
  final String? mediaUrl;
  final String? reaction;
  final DateTime createdAt;
  StoryReply({required this.id, required this.storyId, required this.userId,
    required this.user, this.content, this.mediaUrl, this.reaction, required this.createdAt});
  factory StoryReply.fromJson(Map<String, dynamic> json) => StoryReply(
    id: json['id'], storyId: json['storyId'], userId: json['userId'],
    user: StoryUser.fromJson(json['user']),
    content: json['content'], mediaUrl: json['mediaUrl'], reaction: json['reaction'],
    createdAt: DateTime.parse(json['createdAt']),
  );
}
