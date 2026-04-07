/// Safety Walk status enum matching backend SafetyWalkStatus
enum SafetyWalkStatus {
  pending('PENDING'),
  accepted('ACCEPTED'),
  active('ACTIVE'),
  completed('COMPLETED'),
  cancelled('CANCELLED'),
  sosTriggered('SOS_TRIGGERED');

  final String value;
  const SafetyWalkStatus(this.value);

  factory SafetyWalkStatus.fromString(String s) {
    return values.firstWhere(
      (e) => e.value == s || e.name == s.toLowerCase(),
      orElse: () => pending,
    );
  }
}

/// User model for safety walk participants
class SafetyWalkUser {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? avatarConfig;
  final bool isOnline;
  final String? universityName;

  SafetyWalkUser({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.avatarConfig,
    this.isOnline = false,
    this.universityName,
  });

  factory SafetyWalkUser.fromJson(Map<String, dynamic> json) {
    return SafetyWalkUser(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      displayName: json['displayName'] ?? 'Unknown',
      avatarUrl: json['avatarUrl'],
      avatarConfig: json['avatarConfig'],
      isOnline: json['isOnline'] ?? false,
      universityName: json['universityName'] ?? json['university']?['name'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'avatarConfig': avatarConfig,
    'isOnline': isOnline,
    'universityName': universityName,
  };
}

/// Main Safety Walk model
class SafetyWalk {
  final String id;
  final String requesterId;
  final String companionId;
  final SafetyWalkStatus status;
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final List<Map<String, double>>? routePolyline;
  final int? estimatedDuration;
  final String transportMode;
  final DateTime? scheduledAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final double? safetyScore;
  final bool sosTriggered;
  final String? chatId;
  final SafetyWalkUser? requester;
  final SafetyWalkUser? companion;
  final DateTime createdAt;

  SafetyWalk({
    required this.id,
    required this.requesterId,
    required this.companionId,
    required this.status,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    this.routePolyline,
    this.estimatedDuration,
    this.transportMode = 'WALKING',
    this.scheduledAt,
    this.startedAt,
    this.endedAt,
    this.safetyScore,
    this.sosTriggered = false,
    this.chatId,
    this.requester,
    this.companion,
    required this.createdAt,
  });

  factory SafetyWalk.fromJson(Map<String, dynamic> json) {
    // Parse route polyline - can be list of {lat, lng} or null
    List<Map<String, double>>? polyline;
    if (json['routePolyline'] != null) {
      final polyData = json['routePolyline'];
      if (polyData is List) {
        polyline = polyData.map<Map<String, double>>((p) {
          if (p is Map) {
            return <String, double>{
              'lat': (p['lat'] ?? p['latitude'] ?? 0).toDouble(),
              'lng': (p['lng'] ?? p['longitude'] ?? 0).toDouble(),
            };
          }
          return <String, double>{'lat': 0.0, 'lng': 0.0};
        }).toList();
      }
    }

    return SafetyWalk(
      id: json['id'] ?? '',
      requesterId: json['requesterId'] ?? '',
      companionId: json['companionId'] ?? '',
      status: SafetyWalkStatus.fromString(json['status'] ?? 'PENDING'),
      startLat: (json['startLat'] ?? 0).toDouble(),
      startLng: (json['startLng'] ?? 0).toDouble(),
      endLat: (json['endLat'] ?? 0).toDouble(),
      endLng: (json['endLng'] ?? 0).toDouble(),
      routePolyline: polyline,
      estimatedDuration: json['estimatedDuration'] as int?,
      transportMode: json['transportMode'] ?? 'WALKING',
      scheduledAt: json['scheduledAt'] != null ? DateTime.parse(json['scheduledAt']) : null,
      startedAt: json['startedAt'] != null ? DateTime.parse(json['startedAt']) : null,
      endedAt: json['endedAt'] != null ? DateTime.parse(json['endedAt']) : null,
      safetyScore: json['safetyScore']?.toDouble(),
      sosTriggered: json['sosTriggered'] ?? false,
      chatId: json['chatId'] ?? json['chat']?['id'],
      requester: json['requester'] != null
          ? SafetyWalkUser.fromJson(json['requester'] as Map<String, dynamic>)
          : null,
      companion: json['companion'] != null
          ? SafetyWalkUser.fromJson(json['companion'] as Map<String, dynamic>)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'requesterId': requesterId,
    'companionId': companionId,
    'status': status.value,
    'startLat': startLat,
    'startLng': startLng,
    'endLat': endLat,
    'endLng': endLng,
    'routePolyline': routePolyline,
    'estimatedDuration': estimatedDuration,
    'transportMode': transportMode,
    'scheduledAt': scheduledAt?.toIso8601String(),
    'startedAt': startedAt?.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'safetyScore': safetyScore,
    'sosTriggered': sosTriggered,
    'chatId': chatId,
    'requester': requester?.toJson(),
    'companion': companion?.toJson(),
    'createdAt': createdAt.toIso8601String(),
  };

  SafetyWalk copyWith({
    String? id,
    String? requesterId,
    String? companionId,
    SafetyWalkStatus? status,
    double? startLat,
    double? startLng,
    double? endLat,
    double? endLng,
    List<Map<String, double>>? routePolyline,
    int? estimatedDuration,
    String? transportMode,
    DateTime? scheduledAt,
    DateTime? startedAt,
    DateTime? endedAt,
    double? safetyScore,
    bool? sosTriggered,
    String? chatId,
    SafetyWalkUser? requester,
    SafetyWalkUser? companion,
    DateTime? createdAt,
  }) {
    return SafetyWalk(
      id: id ?? this.id,
      requesterId: requesterId ?? this.requesterId,
      companionId: companionId ?? this.companionId,
      status: status ?? this.status,
      startLat: startLat ?? this.startLat,
      startLng: startLng ?? this.startLng,
      endLat: endLat ?? this.endLat,
      endLng: endLng ?? this.endLng,
      routePolyline: routePolyline ?? this.routePolyline,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      transportMode: transportMode ?? this.transportMode,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      safetyScore: safetyScore ?? this.safetyScore,
      sosTriggered: sosTriggered ?? this.sosTriggered,
      chatId: chatId ?? this.chatId,
      requester: requester ?? this.requester,
      companion: companion ?? this.companion,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Check if current user is the requester
  bool isRequester(String userId) => requesterId == userId;

  /// Get the other participant based on current user
  SafetyWalkUser? getOtherParticipant(String currentUserId) {
    return currentUserId == requesterId ? companion : requester;
  }
}

/// Companion candidate for walk request
class SafetyWalkCompanion {
  final SafetyWalkUser user;
  final double safetyScore;
  final double distance;
  final String friendshipLevel;
  final String? universityName;

  SafetyWalkCompanion({
    required this.user,
    required this.safetyScore,
    required this.distance,
    required this.friendshipLevel,
    this.universityName,
  });

  factory SafetyWalkCompanion.fromJson(Map<String, dynamic> json) {
    return SafetyWalkCompanion(
      user: SafetyWalkUser(
        id: json['id'] ?? '',
        username: json['username'] ?? '',
        displayName: json['displayName'] ?? 'Unknown',
        avatarUrl: json['avatarUrl'],
        avatarConfig: json['avatarConfig'],
        isOnline: true,
        universityName: json['universityName'],
      ),
      safetyScore: (json['safetyScore'] ?? 80).toDouble(),
      distance: (json['distance'] ?? 0).toDouble(),
      friendshipLevel: json['friendshipLevel'] ?? 'NORMAL',
      universityName: json['universityName'],
    );
  }

  /// Format distance for display
  String get formattedDistance {
    if (distance < 1000) {
      return '${distance.toStringAsFixed(0)}m';
    }
    return '${(distance / 1000).toStringAsFixed(1)}km';
  }

  /// Get display label for friendship level
  String get friendshipLabel {
    switch (friendshipLevel) {
      case 'BEST':
        return 'Best Friend';
      case 'CLOSE':
        return 'Close Friend';
      case 'NORMAL':
        return 'Friend';
      case 'SAME_UNIVERSITY':
        return universityName ?? 'Same University';
      default:
        return 'Friend';
    }
  }
}

/// User's safety score
class SafetyScore {
  final String id;
  final double score;
  final int totalWalks;
  final int completedWalks;
  final int cancelledWalks;
  final int sosCount;
  final double avgRating;
  final DateTime lastUpdatedAt;

  SafetyScore({
    required this.id,
    required this.score,
    this.totalWalks = 0,
    this.completedWalks = 0,
    this.cancelledWalks = 0,
    this.sosCount = 0,
    this.avgRating = 5.0,
    required this.lastUpdatedAt,
  });

  factory SafetyScore.fromJson(Map<String, dynamic> json) {
    return SafetyScore(
      id: json['id'] ?? '',
      score: (json['score'] ?? 80).toDouble(),
      totalWalks: json['totalWalks'] ?? 0,
      completedWalks: json['completedWalks'] ?? 0,
      cancelledWalks: json['cancelledWalks'] ?? 0,
      sosCount: json['sosCount'] ?? 0,
      avgRating: (json['avgRating'] ?? 5.0).toDouble(),
      lastUpdatedAt: json['lastUpdatedAt'] != null
          ? DateTime.parse(json['lastUpdatedAt'])
          : DateTime.now(),
    );
  }

  /// Get score as percentage string
  String get scorePercentage => '${score.toStringAsFixed(0)}%';

  /// Get completion rate
  double get completionRate {
    if (totalWalks == 0) return 1.0;
    return completedWalks / totalWalks;
  }
}

/// Route option for walk planning
class RouteOption {
  final String mode;
  final int duration;
  final int distance;  // meters
  final String? departureTime;
  final String? arrivalTime;
  final List<RouteLeg> legs;
  final List<Map<String, double>> polylinePoints;
  final String? fare;
  final int? co2;
  final int? calories;
  final int? stopsCount;

  RouteOption({
    required this.mode,
    required this.duration,
    this.distance = 0,
    this.departureTime,
    this.arrivalTime,
    this.legs = const [],
    this.polylinePoints = const [],
    this.fare,
    this.co2,
    this.calories,
    this.stopsCount,
  });

  factory RouteOption.fromJson(Map<String, dynamic> json) {
    // Parse legs
    final legsList = (json['legs'] as List? ?? [])
        .map((l) => RouteLeg.fromJson(l as Map<String, dynamic>))
        .toList();

    // Parse polyline points
    List<Map<String, double>> points = [];
    final polyData = json['polylinePoints'] ?? json['path'];
    if (polyData is List) {
      points = polyData.map<Map<String, double>>((p) {
        if (p is Map) {
          return <String, double>{
            'lat': (p['lat'] ?? p['latitude'] ?? 0).toDouble(),
            'lng': (p['lng'] ?? p['longitude'] ?? 0).toDouble(),
          };
        }
        return <String, double>{'lat': 0.0, 'lng': 0.0};
      }).toList();
    }

    return RouteOption(
      mode: json['mode'] ?? 'walking',
      duration: json['duration'] ?? 0,
      distance: json['distance'] ?? 0,
      departureTime: json['departureTime'],
      arrivalTime: json['arrivalTime'],
      legs: legsList,
      polylinePoints: points,
      fare: json['fare'],
      co2: json['co2'],
      calories: json['calories'],
      stopsCount: json['stopsCount'],
    );
  }

  /// Format distance for display
  String get formattedDistance {
    if (distance < 1000) {
      return '${distance}m';
    }
    return '${(distance / 1000).toStringAsFixed(1)} km';
  }

  /// Format duration for display
  String get formattedDuration {
    if (duration < 60) {
      return '$duration min';
    }
    final hours = duration ~/ 60;
    final mins = duration % 60;
    return mins > 0 ? '${hours}h ${mins}min' : '${hours}h';
  }

  /// Format departure time (HH:mm)
  String? get formattedDepartureTime {
    if (departureTime == null) return null;
    try {
      final dt = DateTime.parse(departureTime!);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  /// Format arrival time (HH:mm)
  String? get formattedArrivalTime {
    if (arrivalTime == null) return null;
    try {
      final dt = DateTime.parse(arrivalTime!);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  /// Get icon name for mode
  String get modeIcon {
    switch (mode.toLowerCase()) {
      case 'walking':
        return 'directions_walk';
      case 'bus':
        return 'directions_bus';
      case 'tube':
        return 'subway';
      case 'mixed':
        return 'transfer_within_a_station';
      default:
        return 'directions';
    }
  }
}

/// Individual leg of a route
class RouteLeg {
  final String mode;
  final int duration;
  final int distance;  // meters
  final String instruction;
  final String departurePoint;
  final String arrivalPoint;
  final List<Map<String, double>> path;
  final String? lineId;
  final String? lineName;
  final String? lineColor;
  final int? stops;
  final String? direction;

  RouteLeg({
    required this.mode,
    required this.duration,
    this.distance = 0,
    required this.instruction,
    required this.departurePoint,
    required this.arrivalPoint,
    this.path = const [],
    this.lineId,
    this.lineName,
    this.lineColor,
    this.stops,
    this.direction,
  });

  factory RouteLeg.fromJson(Map<String, dynamic> json) {
    // Parse path points
    List<Map<String, double>> pathPoints = [];
    final pathData = json['path'];
    if (pathData is List) {
      pathPoints = pathData.map<Map<String, double>>((p) {
        if (p is Map) {
          return <String, double>{
            'lat': (p['lat'] ?? p['latitude'] ?? 0).toDouble(),
            'lng': (p['lng'] ?? p['longitude'] ?? 0).toDouble(),
          };
        }
        return <String, double>{'lat': 0.0, 'lng': 0.0};
      }).toList();
    }

    return RouteLeg(
      mode: json['mode'] ?? 'walking',
      duration: json['duration'] ?? 0,
      distance: json['distance'] ?? 0,
      instruction: json['instruction'] ?? '',
      departurePoint: json['departurePoint'] ?? json['from'] ?? '',
      arrivalPoint: json['arrivalPoint'] ?? json['to'] ?? '',
      path: pathPoints,
      lineId: json['lineId'],
      lineName: json['lineName'],
      lineColor: json['lineColor'],
      stops: json['stops'],
      direction: json['direction'],
    );
  }
}

/// Nearby transport stop
class NearbyStop {
  final String id;
  final String name;
  final String stopType;
  final double lat;
  final double lng;
  final double distance;
  final List<String> lines;

  NearbyStop({
    required this.id,
    required this.name,
    required this.stopType,
    required this.lat,
    required this.lng,
    required this.distance,
    this.lines = const [],
  });

  factory NearbyStop.fromJson(Map<String, dynamic> json) {
    return NearbyStop(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Stop',
      stopType: json['stopType'] ?? json['modes']?.first ?? 'bus',
      lat: (json['lat'] ?? json['latitude'] ?? 0).toDouble(),
      lng: (json['lng'] ?? json['longitude'] ?? 0).toDouble(),
      distance: (json['distance'] ?? 0).toDouble(),
      lines: (json['lines'] as List? ?? []).map((l) => l.toString()).toList(),
    );
  }

  /// Format distance for display
  String get formattedDistance {
    if (distance < 1000) {
      return '${distance.toStringAsFixed(0)}m';
    }
    return '${(distance / 1000).toStringAsFixed(1)}km';
  }
}

/// Location update during a walk
class SafetyWalkLocation {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final DateTime timestamp;

  SafetyWalkLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.speed,
    this.heading,
    required this.timestamp,
  });

  factory SafetyWalkLocation.fromJson(Map<String, dynamic> json) {
    return SafetyWalkLocation(
      latitude: (json['latitude'] ?? json['lat'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? json['lng'] ?? 0).toDouble(),
      accuracy: json['accuracy']?.toDouble(),
      speed: json['speed']?.toDouble(),
      heading: json['heading']?.toDouble(),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'speed': speed,
    'heading': heading,
  };
}

/// Walk history item with stats
class WalkHistoryItem {
  final SafetyWalk walk;
  final int? duration;
  final double? distance;

  WalkHistoryItem({
    required this.walk,
    this.duration,
    this.distance,
  });

  factory WalkHistoryItem.fromJson(Map<String, dynamic> json) {
    return WalkHistoryItem(
      walk: SafetyWalk.fromJson(json),
      duration: json['stats']?['duration'],
      distance: json['stats']?['distance']?.toDouble(),
    );
  }
}

/// Walk completion stats
class WalkStats {
  final int duration;
  final double distance;

  WalkStats({
    required this.duration,
    required this.distance,
  });

  factory WalkStats.fromJson(Map<String, dynamic> json) {
    return WalkStats(
      duration: json['duration'] ?? 0,
      distance: (json['distance'] ?? 0).toDouble(),
    );
  }

  /// Format duration for display
  String get formattedDuration {
    if (duration < 60) {
      return '$duration sec';
    }
    final mins = duration ~/ 60;
    final secs = duration % 60;
    if (mins < 60) {
      return secs > 0 ? '$mins min $secs sec' : '$mins min';
    }
    final hours = mins ~/ 60;
    final remainMins = mins % 60;
    return remainMins > 0 ? '${hours}h ${remainMins}m' : '${hours}h';
  }

  /// Format distance for display
  String get formattedDistance {
    if (distance < 1000) {
      return '${distance.toStringAsFixed(0)}m';
    }
    return '${(distance / 1000).toStringAsFixed(2)}km';
  }
}

/// SOS emergency result
class SOSResult {
  final bool emergency;
  final SafetyWalkLocation? companionLocation;
  final int emergencyContacts;

  SOSResult({
    required this.emergency,
    this.companionLocation,
    this.emergencyContacts = 0,
  });

  factory SOSResult.fromJson(Map<String, dynamic> json) {
    return SOSResult(
      emergency: json['emergency'] ?? true,
      companionLocation: json['companionLocation'] != null
          ? SafetyWalkLocation(
              latitude: (json['companionLocation']['lat'] ?? 0).toDouble(),
              longitude: (json['companionLocation']['lng'] ?? 0).toDouble(),
              timestamp: DateTime.now(),
            )
          : null,
      emergencyContacts: json['emergencyContacts'] ?? 0,
    );
  }
}
