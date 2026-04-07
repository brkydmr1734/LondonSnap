import 'dart:convert';

enum ChatType {
  direct('DIRECT'),
  group('GROUP');

  final String value;
  const ChatType(this.value);
  factory ChatType.fromString(String s) =>
      values.firstWhere((e) => e.value == s, orElse: () => direct);
}

/// Message delivery/read status
enum MessageStatus {
  /// Message is being sent
  sending,
  /// Message sent to server
  sent,
  /// Message delivered to recipient device (not used currently)
  delivered,
  /// Message has been read by recipient
  read,
  /// Message failed to send
  failed,
}

enum MessageType {
  text('TEXT'),
  image('IMAGE'),
  video('VIDEO'),
  audio('AUDIO'),
  snap('SNAP'),
  sticker('STICKER'),
  location('LOCATION'),
  system('SYSTEM');

  final String value;
  const MessageType(this.value);
  factory MessageType.fromString(String s) =>
      values.firstWhere((e) => e.value == s, orElse: () => text);
}

class Chat {
  final String id;
  final ChatType type;
  final String? name;
  final String? imageUrl;
  final List<ChatParticipant> participants;
  final Message? lastMessage;
  final int unreadCount;
  final bool isMuted;
  final bool isPinned;
  final bool isDisappearing;
  final int? disappearAfter;
  final String? backgroundUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  Chat({
    required this.id, required this.type, this.name, this.imageUrl,
    required this.participants, this.lastMessage,
    this.unreadCount = 0, this.isMuted = false, this.isPinned = false,
    this.isDisappearing = false, this.disappearAfter, this.backgroundUrl,
    required this.createdAt, required this.updatedAt,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    // Prefer 'otherMembers' (excludes current user) so display only shows chat partner
    final membersList = json['otherMembers'] as List? ?? json['members'] as List? ?? [];
    return Chat(
      id: json['id'],
      type: ChatType.fromString(json['type'] ?? 'DIRECT'),
      name: json['name'],
      imageUrl: json['imageUrl'],
      participants: membersList
          .map((p) => ChatParticipant.fromJson(p as Map<String, dynamic>)).toList(),
      lastMessage: json['lastMessage'] != null
          ? Message.fromJson(json['lastMessage']) : null,
      unreadCount: json['unreadCount'] ?? 0,
      isMuted: json['isMuted'] ?? false,
      isPinned: json['isPinned'] ?? false,
      isDisappearing: json['isDisappearing'] ?? false,
      disappearAfter: json['disappearAfter'],
      backgroundUrl: json['backgroundUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt'] ?? json['lastMessageAt'] ?? json['createdAt']),
    );
  }

  /// Create a copy with updated disappearing settings
  Chat copyWithDisappearing({bool? isDisappearing, int? disappearAfter, bool clearDisappearAfter = false}) {
    return Chat(
      id: id, type: type, name: name, imageUrl: imageUrl,
      participants: participants, lastMessage: lastMessage,
      unreadCount: unreadCount, isMuted: isMuted, isPinned: isPinned,
      isDisappearing: isDisappearing ?? this.isDisappearing,
      disappearAfter: clearDisappearAfter ? null : (disappearAfter ?? this.disappearAfter),
      backgroundUrl: backgroundUrl,
      createdAt: createdAt, updatedAt: updatedAt,
    );
  }

  Chat copyWithBackground(String? newBackgroundUrl) {
    return Chat(
      id: id, type: type, name: name, imageUrl: imageUrl,
      participants: participants, lastMessage: lastMessage,
      unreadCount: unreadCount, isMuted: isMuted, isPinned: isPinned,
      isDisappearing: isDisappearing, disappearAfter: disappearAfter,
      backgroundUrl: newBackgroundUrl,
      createdAt: createdAt, updatedAt: updatedAt,
    );
  }

  String displayName(String currentUserId) {
    if (name != null) return name!;
    final other = participants.where((p) => p.user.id != currentUserId).toList();
    if (other.isEmpty) return 'Chat';
    return other.map((p) => p.user.displayName).join(', ');
  }
}

class ChatParticipant {
  final String id;
  final ChatUser user;
  final String role;
  final DateTime joinedAt;

  ChatParticipant({required this.id, required this.user, this.role = 'MEMBER', required this.joinedAt});

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    return ChatParticipant(
      id: json['id'],
      user: ChatUser.fromJson(json['user'] as Map<String, dynamic>),
      role: json['role'] ?? 'MEMBER',
      joinedAt: json['joinedAt'] != null ? DateTime.parse(json['joinedAt']) : DateTime.now(),
    );
  }
}

class ChatUser {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarConfig;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final String? emoji;
  final String? emojiLabel;

  ChatUser({
    required this.id, this.username = '', required this.displayName,
    this.avatarUrl, this.avatarConfig, this.isOnline = false, this.lastSeenAt,
    this.emoji, this.emojiLabel,
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      id: json['id'], username: json['username'] ?? '',
      displayName: json['displayName'] ?? 'Unknown',
      avatarUrl: json['avatarUrl'],
      avatarConfig: json['avatarConfig'],
      isOnline: json['isOnline'] ?? false,
      lastSeenAt: json['lastSeenAt'] != null ? DateTime.parse(json['lastSeenAt']) : null,
      emoji: json['emoji'],
      emojiLabel: json['emojiLabel'],
    );
  }
}

class Message {
  final String id;
  final String chatId;
  final String senderId;
  final ChatUser? sender;
  final MessageType type;
  final String content;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final int? duration; // seconds, for audio/video messages
  final ReplyMessage? replyTo;
  final List<MessageReaction> reactions;
  final List<ReadReceipt> readBy;
  final DateTime? deliveredAt;
  final bool isEdited;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final MessageStatus status;

  Message({
    required this.id, required this.chatId, required this.senderId,
    this.sender, required this.type, required this.content,
    this.mediaUrl, this.thumbnailUrl, this.duration, this.replyTo,
    this.reactions = const [], this.readBy = const [],
    this.deliveredAt,
    this.isEdited = false, this.expiresAt, required this.createdAt,
    this.status = MessageStatus.sent,
  });

  /// Create a copy with updated status
  Message copyWithStatus(MessageStatus newStatus) {
    return Message(
      id: id, chatId: chatId, senderId: senderId, sender: sender,
      type: type, content: content, mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl, duration: duration, replyTo: replyTo,
      reactions: reactions, readBy: readBy, 
      deliveredAt: newStatus == MessageStatus.delivered ? DateTime.now() : deliveredAt,
      isEdited: isEdited,
      expiresAt: expiresAt, createdAt: createdAt, status: newStatus,
    );
  }

  /// Create a copy with updated readBy list
  Message copyWithReadBy(List<ReadReceipt> newReadBy) {
    return Message(
      id: id, chatId: chatId, senderId: senderId, sender: sender,
      type: type, content: content, mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl, duration: duration, replyTo: replyTo,
      reactions: reactions, readBy: newReadBy, 
      deliveredAt: deliveredAt,
      isEdited: isEdited,
      expiresAt: expiresAt, createdAt: createdAt,
      status: newReadBy.isNotEmpty ? MessageStatus.read : status,
    );
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    final readByList = (json['readReceipts'] as List? ?? json['readBy'] as List? ?? [])
        .map((r) => ReadReceipt.fromJson(r)).toList();
    final deliveredAtStr = json['deliveredAt'] as String?;
    final deliveredAt = deliveredAtStr != null ? DateTime.tryParse(deliveredAtStr) : null;
    
    // Determine status: read > delivered > sent
    MessageStatus status;
    if (readByList.isNotEmpty) {
      status = MessageStatus.read;
    } else if (deliveredAt != null) {
      status = MessageStatus.delivered;
    } else {
      status = MessageStatus.sent;
    }
    
    return Message(
      id: json['id'], chatId: json['chatId'], senderId: json['senderId'],
      sender: json['sender'] != null ? ChatUser.fromJson(json['sender']) : null,
      type: MessageType.fromString(json['type'] ?? 'TEXT'),
      content: json['content'] ?? '',
      mediaUrl: json['mediaUrl'], thumbnailUrl: json['thumbnailUrl'],
      duration: json['duration'] as int?,
      replyTo: json['replyTo'] != null ? ReplyMessage.fromJson(json['replyTo']) : null,
      reactions: (json['reactions'] as List? ?? [])
          .map((r) => MessageReaction.fromJson(r)).toList(),
      readBy: readByList,
      deliveredAt: deliveredAt,
      isEdited: json['isEdited'] ?? false,
      expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt']) : null,
      createdAt: DateTime.parse(json['createdAt']),
      status: status,
    );
  }

  /// Check if this message is a snap message
  bool get isSnapMessage => type == MessageType.snap;

  /// Parse snap data from message content (only valid for snap messages)
  SnapMessageData? get snapData {
    if (!isSnapMessage || content.isEmpty) return null;
    return SnapMessageData.fromJson(content);
  }

  /// Create a copy with updated content (for snap status updates)
  Message copyWithContent(String newContent) {
    return Message(
      id: id, chatId: chatId, senderId: senderId, sender: sender,
      type: type, content: newContent, mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl, replyTo: replyTo,
      reactions: reactions, readBy: readBy, 
      deliveredAt: deliveredAt,
      isEdited: isEdited,
      expiresAt: expiresAt, createdAt: createdAt, status: status,
    );
  }
}

class ReplyMessage {
  final String id;
  final String senderId;
  final String? senderName;
  final String content;
  final MessageType type;

  ReplyMessage({required this.id, required this.senderId, this.senderName,
    required this.content, this.type = MessageType.text});

  factory ReplyMessage.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] as Map<String, dynamic>?;
    return ReplyMessage(
      id: json['id'],
      senderId: json['senderId'] ?? sender?['id'] ?? '',
      senderName: json['senderName'] ?? sender?['displayName'],
      content: json['content'] ?? '',
      type: MessageType.fromString(json['type'] ?? 'TEXT'),
    );
  }
}

class MessageReaction {
  final String id;
  final String userId;
  final String emoji;
  final DateTime createdAt;

  MessageReaction({required this.id, required this.userId, required this.emoji, required this.createdAt});

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      id: json['id'], userId: json['userId'],
      emoji: json['emoji'], createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class ReadReceipt {
  final String userId;
  final DateTime readAt;

  ReadReceipt({required this.userId, required this.readAt});

  factory ReadReceipt.fromJson(Map<String, dynamic> json) {
    return ReadReceipt(userId: json['userId'], readAt: DateTime.parse(json['readAt']));
  }
}

/// Snap message status - matches backend SnapStatus enum
enum SnapStatus {
  sent('SENT'),
  delivered('DELIVERED'),
  opened('OPENED'),
  replayed('REPLAYED'),
  screenshot('SCREENSHOT');

  final String value;
  const SnapStatus(this.value);
  factory SnapStatus.fromString(String s) =>
      values.firstWhere((e) => e.value == s, orElse: () => sent);
}

/// Snap media type
enum SnapMediaType {
  image('IMAGE'),
  video('VIDEO');

  final String value;
  const SnapMediaType(this.value);
  factory SnapMediaType.fromString(String s) =>
      values.firstWhere((e) => e.value == s, orElse: () => image);
}

/// Parsed data for SNAP type messages
class SnapMessageData {
  final String snapId;
  final SnapMediaType mediaType;
  final SnapStatus status;

  SnapMessageData({
    required this.snapId,
    required this.mediaType,
    required this.status,
  });

  /// Parse from the JSON string stored in message.content
  factory SnapMessageData.fromJson(String jsonString) {
    try {
      final Map<String, dynamic> json = jsonDecode(jsonString) as Map<String, dynamic>;
      return SnapMessageData(
        snapId: json['snapId'] as String? ?? '',
        mediaType: SnapMediaType.fromString(json['mediaType'] as String? ?? 'IMAGE'),
        status: SnapStatus.fromString(json['status'] as String? ?? 'SENT'),
      );
    } catch (_) {
      return SnapMessageData(
        snapId: '',
        mediaType: SnapMediaType.image,
        status: SnapStatus.sent,
      );
    }
  }

  /// Create updated snap data with new status
  SnapMessageData copyWithStatus(SnapStatus newStatus) {
    return SnapMessageData(
      snapId: snapId,
      mediaType: mediaType,
      status: newStatus,
    );
  }

  /// Serialize back to JSON string for message content
  String toJsonString() {
    return '{"snapId":"$snapId","mediaType":"${mediaType.value}","status":"${status.value}"}';
  }

  /// Check if this is an image snap
  bool get isImage => mediaType == SnapMediaType.image;

  /// Check if this is a video snap
  bool get isVideo => mediaType == SnapMediaType.video;

  /// Check if snap has been opened/viewed
  bool get isOpened => status == SnapStatus.opened || status == SnapStatus.replayed;

  /// Check if snap was screenshotted
  bool get isScreenshot => status == SnapStatus.screenshot;
}
