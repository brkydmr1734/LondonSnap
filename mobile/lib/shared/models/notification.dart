import 'package:flutter/material.dart';

/// Notification types matching backend enum.
enum NotificationType {
  snapReceived('SNAP_RECEIVED'),
  snapOpened('SNAP_OPENED'),
  snapScreenshot('SNAP_SCREENSHOT'),
  message('MESSAGE'),
  friendRequest('FRIEND_REQUEST'),
  friendAccepted('FRIEND_ACCEPTED'),
  storyReaction('STORY_REACTION'),
  storyReply('STORY_REPLY'),
  eventInvite('EVENT_INVITE'),
  eventReminder('EVENT_REMINDER'),
  streakWarning('STREAK_WARNING'),
  streakLost('STREAK_LOST');

  final String value;
  const NotificationType(this.value);

  static NotificationType fromString(String value) {
    return NotificationType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => NotificationType.message,
    );
  }

  /// Get icon for notification type.
  IconData get icon {
    switch (this) {
      case NotificationType.snapReceived:
      case NotificationType.snapOpened:
      case NotificationType.snapScreenshot:
        return Icons.camera_alt_rounded;
      case NotificationType.message:
        return Icons.chat_bubble_rounded;
      case NotificationType.friendRequest:
      case NotificationType.friendAccepted:
        return Icons.person_add_rounded;
      case NotificationType.storyReaction:
        return Icons.favorite_rounded;
      case NotificationType.storyReply:
        return Icons.reply_rounded;
      case NotificationType.eventInvite:
      case NotificationType.eventReminder:
        return Icons.event_rounded;
      case NotificationType.streakWarning:
      case NotificationType.streakLost:
        return Icons.local_fire_department_rounded;
    }
  }

  /// Get color for notification type.
  Color get color {
    switch (this) {
      case NotificationType.snapReceived:
      case NotificationType.snapOpened:
      case NotificationType.snapScreenshot:
        return const Color(0xFFEC4899); // Pink
      case NotificationType.message:
        return const Color(0xFF6366F1); // Primary
      case NotificationType.friendRequest:
      case NotificationType.friendAccepted:
        return const Color(0xFF10B981); // Green
      case NotificationType.storyReaction:
        return const Color(0xFFEF4444); // Red
      case NotificationType.storyReply:
        return const Color(0xFF8B5CF6); // Purple
      case NotificationType.eventInvite:
      case NotificationType.eventReminder:
        return const Color(0xFFF59E0B); // Amber
      case NotificationType.streakWarning:
      case NotificationType.streakLost:
        return const Color(0xFFF97316); // Orange
    }
  }
}

/// App notification model.
class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final String? imageUrl;
  final Map<String, dynamic>? data;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.imageUrl,
    this.data,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      type: NotificationType.fromString(json['type'] as String),
      title: json['title'] as String,
      body: json['body'] as String,
      imageUrl: json['imageUrl'] as String?,
      data: json['data'] != null ? Map<String, dynamic>.from(json['data']) : null,
      isRead: json['isRead'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.value,
      'title': title,
      'body': body,
      'imageUrl': imageUrl,
      'data': data,
      'isRead': isRead,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  AppNotification copyWith({
    String? id,
    NotificationType? type,
    String? title,
    String? body,
    String? imageUrl,
    Map<String, dynamic>? data,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      imageUrl: imageUrl ?? this.imageUrl,
      data: data ?? this.data,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
