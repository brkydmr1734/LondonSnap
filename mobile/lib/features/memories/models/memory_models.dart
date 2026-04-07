class MemoryAlbum {
  final String id;
  final String name;
  final String? coverUrl;
  final bool isPrivate;
  final int memoryCount;
  final DateTime createdAt;
  final DateTime? updatedAt;

  MemoryAlbum({
    required this.id,
    required this.name,
    this.coverUrl,
    required this.isPrivate,
    required this.memoryCount,
    required this.createdAt,
    this.updatedAt,
  });

  factory MemoryAlbum.fromJson(Map<String, dynamic> json) {
    return MemoryAlbum(
      id: json['id'] as String,
      name: json['name'] as String,
      coverUrl: json['coverUrl'] as String?,
      isPrivate: json['isPrivate'] as bool? ?? true,
      memoryCount: json['memoryCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'coverUrl': coverUrl,
      'isPrivate': isPrivate,
      'memoryCount': memoryCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

class Memory {
  final String id;
  final String userId;
  final String mediaUrl;
  final String mediaType;
  final String? thumbnailUrl;
  final String? caption;
  final String? location;
  final double? latitude;
  final double? longitude;
  final DateTime takenAt;
  final DateTime createdAt;
  final MemoryAlbum? album;
  final bool isMyEyesOnly;

  Memory({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    required this.mediaType,
    this.thumbnailUrl,
    this.caption,
    this.location,
    this.latitude,
    this.longitude,
    required this.takenAt,
    required this.createdAt,
    this.album,
    this.isMyEyesOnly = false,
  });

  factory Memory.fromJson(Map<String, dynamic> json) {
    return Memory(
      id: json['id'] as String,
      userId: json['userId'] as String,
      mediaUrl: json['mediaUrl'] as String,
      mediaType: json['mediaType'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      caption: json['caption'] as String?,
      location: json['location'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      takenAt: DateTime.parse(json['takenAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      album: json['album'] != null
          ? MemoryAlbum.fromJson(json['album'] as Map<String, dynamic>)
          : null,
      isMyEyesOnly: json['isMyEyesOnly'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'thumbnailUrl': thumbnailUrl,
      'caption': caption,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'takenAt': takenAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'album': album?.toJson(),
      'isMyEyesOnly': isMyEyesOnly,
    };
  }

  Memory copyWith({
    String? id,
    String? userId,
    String? mediaUrl,
    String? mediaType,
    String? thumbnailUrl,
    String? caption,
    String? location,
    double? latitude,
    double? longitude,
    DateTime? takenAt,
    DateTime? createdAt,
    MemoryAlbum? album,
    bool? isMyEyesOnly,
  }) {
    return Memory(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      caption: caption ?? this.caption,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      takenAt: takenAt ?? this.takenAt,
      createdAt: createdAt ?? this.createdAt,
      album: album ?? this.album,
      isMyEyesOnly: isMyEyesOnly ?? this.isMyEyesOnly,
    );
  }

  bool get isVideo => mediaType == 'VIDEO';
  bool get isImage => mediaType == 'IMAGE';

  /// Check if this memory is from the same date in a previous year
  bool get isOnThisDay {
    final now = DateTime.now();
    return takenAt.month == now.month &&
        takenAt.day == now.day &&
        takenAt.year < now.year;
  }
}

class MemoryPagination {
  final int total;
  final int limit;
  final int offset;
  final bool hasMore;

  MemoryPagination({
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  factory MemoryPagination.fromJson(Map<String, dynamic> json) {
    return MemoryPagination(
      total: json['total'] as int,
      limit: json['limit'] as int,
      offset: json['offset'] as int,
      hasMore: json['hasMore'] as bool,
    );
  }
}
