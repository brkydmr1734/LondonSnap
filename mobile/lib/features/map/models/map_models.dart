import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:londonsnaps/features/discover/models/discover_models.dart';

class MapUserPin {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarConfig;
  final LatLng position;
  final double distance;
  final bool isOnline;
  final String? university;
  final bool isCurrentUser;

  const MapUserPin({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.avatarConfig,
    required this.position,
    this.distance = 0,
    this.isOnline = false,
    this.university,
    this.isCurrentUser = false,
  });

  String get formattedDistance {
    if (distance < 1) return '${(distance * 1000).toInt()}m';
    return '${distance.toStringAsFixed(1)}km';
  }
}

class MapEventPin {
  final String id;
  final String title;
  final String? coverImageUrl;
  final EventCategory category;
  final LatLng position;
  final DateTime startDate;
  final int attendeeCount;
  final bool isFree;
  final double? price;

  const MapEventPin({
    required this.id,
    required this.title,
    this.coverImageUrl,
    required this.category,
    required this.position,
    required this.startDate,
    this.attendeeCount = 0,
    this.isFree = true,
    this.price,
  });

  Color get categoryColor {
    switch (category) {
      case EventCategory.party:
        return const Color(0xFFEC4899);
      case EventCategory.music:
        return const Color(0xFF8B5CF6);
      case EventCategory.sports:
        return const Color(0xFF10B981);
      case EventCategory.academic:
        return const Color(0xFF3B82F6);
      case EventCategory.social:
        return const Color(0xFF6366F1);
      case EventCategory.food:
        return const Color(0xFFF97316);
      case EventCategory.art:
        return const Color(0xFFF59E0B);
      case EventCategory.tech:
        return const Color(0xFF06B6D4);
      case EventCategory.networking:
        return const Color(0xFF84CC16);
      case EventCategory.other:
        return const Color(0xFF6B7280);
    }
  }

  String get formattedTime {
    final now = DateTime.now();
    final diff = startDate.difference(now);
    if (diff.isNegative) return 'Now';
    if (diff.inHours < 1) return 'In ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'In ${diff.inHours}h';
    return 'In ${diff.inDays}d';
  }
}
