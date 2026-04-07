import 'package:flutter/material.dart';

enum EventCategory {
  party('PARTY', 'Party', Icons.celebration),
  music('MUSIC', 'Music', Icons.music_note),
  sports('SPORTS', 'Sports', Icons.sports),
  academic('ACADEMIC', 'Academic', Icons.school),
  social('SOCIAL', 'Social', Icons.people),
  food('FOOD', 'Food & Drinks', Icons.restaurant),
  art('ART', 'Art & Culture', Icons.palette),
  tech('TECH', 'Tech', Icons.computer),
  networking('NETWORKING', 'Networking', Icons.handshake),
  other('OTHER', 'Other', Icons.category);
  final String value;
  final String displayName;
  final IconData icon;
  const EventCategory(this.value, this.displayName, this.icon);
  factory EventCategory.fromString(String s) =>
      values.firstWhere((e) => e.value == s, orElse: () => other);
}

enum MatchType {
  university, area, interests, mutualFriends;
  factory MatchType.fromString(String s) =>
      values.firstWhere((e) => e.name == s.toLowerCase(), orElse: () => interests);
}

class DiscoverEvent {
  final String id;
  final String title;
  final String description;
  final String? coverImageUrl;
  final EventCategory category;
  final EventLocation location;
  final DateTime startDate;
  final DateTime endDate;
  final EventOrganizer organizer;
  final int attendeeCount;
  final int maxAttendees;
  final bool isAttending;
  final bool isFree;
  final double? price;
  final String? currency;
  final List<String> tags;
  final DateTime createdAt;

  DiscoverEvent({
    required this.id, required this.title, required this.description,
    this.coverImageUrl, required this.category, required this.location,
    required this.startDate, required this.endDate, required this.organizer,
    this.attendeeCount = 0, this.maxAttendees = 0, this.isAttending = false,
    this.isFree = true, this.price, this.currency, this.tags = const [],
    required this.createdAt,
  });

  bool get isSoldOut => maxAttendees > 0 && attendeeCount >= maxAttendees;
  bool get isUpcoming => startDate.isAfter(DateTime.now());
  bool get isOngoing => startDate.isBefore(DateTime.now()) && endDate.isAfter(DateTime.now());

  factory DiscoverEvent.fromJson(Map<String, dynamic> json) {
    return DiscoverEvent(
      id: json['id'], title: json['title'], description: json['description'] ?? '',
      coverImageUrl: json['coverImageUrl'],
      category: EventCategory.fromString(json['category'] ?? 'OTHER'),
      location: EventLocation.fromJson(json['location']),
      startDate: DateTime.parse(json['startDate']),
      endDate: DateTime.parse(json['endDate']),
      organizer: EventOrganizer.fromJson(json['organizer']),
      attendeeCount: json['attendeeCount'] ?? 0,
      maxAttendees: json['maxAttendees'] ?? 0,
      isAttending: json['isAttending'] ?? false,
      isFree: json['isFree'] ?? true,
      price: (json['price'] as num?)?.toDouble(),
      currency: json['currency'],
      tags: List<String>.from(json['tags'] ?? []),
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class EventLocation {
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final String? area;
  EventLocation({required this.name, this.address, required this.latitude,
    required this.longitude, this.area});
  factory EventLocation.fromJson(Map<String, dynamic> json) => EventLocation(
    name: json['name'], address: json['address'],
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(), area: json['area'],
  );
}

class EventOrganizer {
  final String id;
  final String name;
  final String? avatarUrl;
  final bool isVerified;
  EventOrganizer({required this.id, required this.name, this.avatarUrl, this.isVerified = false});
  factory EventOrganizer.fromJson(Map<String, dynamic> json) => EventOrganizer(
    id: json['id'], name: json['name'], avatarUrl: json['avatarUrl'],
    isVerified: json['isVerified'] ?? false,
  );
}

class NearbyUser {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final double distance;
  final String? university;
  final int mutualFriends;
  final bool isOnline;

  NearbyUser({required this.id, required this.username, required this.displayName,
    this.avatarUrl, required this.distance, this.university,
    this.mutualFriends = 0, this.isOnline = false});

  String get formattedDistance {
    if (distance < 1) return '${(distance * 1000).toInt()}m';
    return '${distance.toStringAsFixed(1)}km';
  }

  factory NearbyUser.fromJson(Map<String, dynamic> json) => NearbyUser(
    id: json['id'], username: json['username'], displayName: json['displayName'],
    avatarUrl: json['avatarUrl'], distance: (json['distance'] as num?)?.toDouble() ?? 0,
    university: json['university'], mutualFriends: json['mutualFriends'] ?? 0,
    isOnline: json['isOnline'] ?? false,
  );
}

class MatchProfile {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final String? university;
  final MatchType matchType;
  final int matchPercentage;
  final int mutualFriends;
  final List<String> sharedInterests;

  MatchProfile({required this.id, required this.username, required this.displayName,
    this.avatarUrl, this.bio, this.university, required this.matchType,
    this.matchPercentage = 0, this.mutualFriends = 0, this.sharedInterests = const []});

  factory MatchProfile.fromJson(Map<String, dynamic> json) => MatchProfile(
    id: json['id'], username: json['username'], displayName: json['displayName'],
    avatarUrl: json['avatarUrl'], bio: json['bio'], university: json['university'],
    matchType: MatchType.fromString(json['matchType'] ?? 'interests'),
    matchPercentage: json['matchPercentage'] ?? 0,
    mutualFriends: json['mutualFriends'] ?? 0,
    sharedInterests: List<String>.from(json['sharedInterests'] ?? []),
  );
}

class LondonAreaInfo {
  final String name;
  final String description;
  final String emoji;
  final int activeUsers;
  LondonAreaInfo({required this.name, required this.description, required this.emoji, this.activeUsers = 0});

  static List<LondonAreaInfo> get popularAreas => [
    LondonAreaInfo(name: 'Soho', description: 'Nightlife & Entertainment', emoji: '🎭'),
    LondonAreaInfo(name: 'Camden', description: 'Markets & Live Music', emoji: '🎸'),
    LondonAreaInfo(name: 'Shoreditch', description: 'Art & Tech Hub', emoji: '🎨'),
    LondonAreaInfo(name: 'Notting Hill', description: 'Cafés & Portobello', emoji: '🌸'),
    LondonAreaInfo(name: 'Covent Garden', description: 'Theatre & Shopping', emoji: '🎪'),
    LondonAreaInfo(name: 'South Bank', description: 'Culture & River Views', emoji: '🎡'),
    LondonAreaInfo(name: 'Brick Lane', description: 'Food & Street Art', emoji: '🍜'),
    LondonAreaInfo(name: 'Greenwich', description: 'Parks & History', emoji: '🌿'),
  ];
}
