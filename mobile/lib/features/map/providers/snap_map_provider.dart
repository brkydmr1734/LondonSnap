import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/core/config/app_config.dart';
import 'package:londonsnaps/features/discover/models/discover_models.dart';
import 'package:londonsnaps/features/map/models/map_models.dart';
import 'package:londonsnaps/features/map/models/poi_models.dart';

/// Route info returned from Mapbox Directions API
class MapRouteInfo {
  final List<LatLng> polylinePoints;
  final double distanceMeters;
  final double durationSeconds;
  final LatLng destination;
  final String destinationName;

  const MapRouteInfo({
    required this.polylinePoints,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.destination,
    required this.destinationName,
  });

  String get formattedDistance {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters.round()} m';
  }

  String get formattedDuration {
    final minutes = (durationSeconds / 60).round();
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return '${hours}h ${mins}min';
    }
    return '$minutes min';
  }
}

enum MapFilter { all, friends, events }

class SnapMapState {
  final LatLng? userLocation;
  final List<MapUserPin> nearbyUsers;
  final List<MapEventPin> nearbyEvents;
  final MapFilter filter;
  final bool isLocating;
  final bool permissionDenied;
  final String? error;
  final Set<PoiCategory> activePoiFilters;
  final bool showPois;
  final bool ghostMode;
  final MapRouteInfo? activeRoute;
  final bool isLoadingRoute;

  const SnapMapState({
    this.userLocation,
    this.nearbyUsers = const [],
    this.nearbyEvents = const [],
    this.filter = MapFilter.all,
    this.isLocating = false,
    this.permissionDenied = false,
    this.error,
    this.activePoiFilters = const {},
    this.showPois = true,
    this.ghostMode = false,
    this.activeRoute,
    this.isLoadingRoute = false,
  });

  List<Object> get visiblePins {
    switch (filter) {
      case MapFilter.friends:
        return nearbyUsers;
      case MapFilter.events:
        return nearbyEvents;
      case MapFilter.all:
        return [...nearbyUsers, ...nearbyEvents];
    }
  }

  /// Filtered POIs based on active filters. Empty set = show all.
  List<PoiPin> get visiblePois {
    if (!showPois) return [];
    if (activePoiFilters.isEmpty) return LondonPois.all;
    return LondonPois.all
        .where((p) => activePoiFilters.contains(p.category))
        .toList();
  }

  SnapMapState copyWith({
    LatLng? userLocation,
    List<MapUserPin>? nearbyUsers,
    List<MapEventPin>? nearbyEvents,
    MapFilter? filter,
    bool? isLocating,
    bool? permissionDenied,
    String? error,
    Set<PoiCategory>? activePoiFilters,
    bool? showPois,
    bool? ghostMode,
    MapRouteInfo? activeRoute,
    bool clearRoute = false,
    bool? isLoadingRoute,
  }) {
    return SnapMapState(
      userLocation: userLocation ?? this.userLocation,
      nearbyUsers: nearbyUsers ?? this.nearbyUsers,
      nearbyEvents: nearbyEvents ?? this.nearbyEvents,
      filter: filter ?? this.filter,
      isLocating: isLocating ?? this.isLocating,
      permissionDenied: permissionDenied ?? this.permissionDenied,
      error: error,
      activePoiFilters: activePoiFilters ?? this.activePoiFilters,
      showPois: showPois ?? this.showPois,
      ghostMode: ghostMode ?? this.ghostMode,
      activeRoute: clearRoute ? null : (activeRoute ?? this.activeRoute),
      isLoadingRoute: isLoadingRoute ?? this.isLoadingRoute,
    );
  }
}

class SnapMapNotifier extends StateNotifier<SnapMapState> {
  final ApiService _api;

  SnapMapNotifier(this._api) : super(const SnapMapState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    state = state.copyWith(isLocating: true);
    // Load ghost mode state and location in parallel
    await Future.wait([
      _loadGhostMode(),
      _requestLocationAndLoad(),
    ]);
  }

  Future<void> _loadGhostMode() async {
    try {
      final response = await _api.getPrivacySettings();
      final settings = response.data['data']?['settings'];
      if (settings != null) {
        final isGhost = settings['whoCanSeeLocation'] == 'NOBODY';
        state = state.copyWith(ghostMode: isGhost);
      }
    } catch (_) {}
  }

  void toggleGhostMode() async {
    final newGhost = !state.ghostMode;
    state = state.copyWith(ghostMode: newGhost);
    try {
      await _api.updatePrivacySettings({
        'whoCanSeeLocation': newGhost ? 'NOBODY' : 'FRIENDS',
        'showInNearby': !newGhost,
      });
    } catch (_) {
      // Revert on failure
      state = state.copyWith(ghostMode: !newGhost);
    }
  }

  Future<void> _requestLocationAndLoad() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        const londonCenter = LatLng(51.5074, -0.1278);
        state = state.copyWith(
          userLocation: londonCenter,
          isLocating: false,
          permissionDenied: true,
        );
        await _loadNearbyData(londonCenter.latitude, londonCenter.longitude);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final loc = LatLng(position.latitude, position.longitude);
      state = state.copyWith(userLocation: loc, isLocating: false);
      // Send location to backend (fire-and-forget)
      _api.updateUserLocation(lat: position.latitude, lng: position.longitude).catchError((_) { return null as dynamic; });
      await _loadNearbyData(position.latitude, position.longitude);
    } catch (e) {
      const londonCenter = LatLng(51.5074, -0.1278);
      state = state.copyWith(userLocation: londonCenter, isLocating: false);
      await _loadNearbyData(londonCenter.latitude, londonCenter.longitude);
    }
  }

  Future<void> _loadNearbyData(double lat, double lng) async {
    try {
      Future<dynamic> safeCall(Future<dynamic> f) async {
        try {
          return await f;
        } catch (_) {
          return null;
        }
      }

      final results = await Future.wait([
        safeCall(_api.getFriendLocations()),
        safeCall(_api.getEvents(lat: lat, lng: lng)),
      ]);

      final userPins = _parseUserPins(results[0], lat, lng);
      final eventPins = _parseEventPins(results[1], lat, lng);

      state = state.copyWith(
        nearbyUsers: userPins,
        nearbyEvents: eventPins,
      );
    } catch (_) {
      state = state.copyWith(
        nearbyUsers: [],
        nearbyEvents: [],
      );
    }
  }

  List<MapUserPin> _parseUserPins(dynamic response, double lat, double lng) {
    if (response == null) return [];
    try {
      final data = response.data;
      final raw = data is Map
          ? (data['data']?['users'] ?? data['data'] ?? [])
          : [];
      final list = raw as List;
      return list.asMap().entries.map((entry) {
        final i = entry.key;
        final u = entry.value;
        return MapUserPin(
          id: u['id'] ?? 'user_$i',
          username: u['username'] ?? '',
          displayName: u['displayName'] ?? u['username'] ?? '',
          avatarUrl: u['avatarUrl'],
          avatarConfig: u['avatarConfig'],
          position: LatLng(
            (u['latitude'] as num?)?.toDouble() ?? lat,
            (u['longitude'] as num?)?.toDouble() ?? lng,
          ),
          distance: (u['distance'] as num?)?.toDouble() ?? 0.5,
          isOnline: u['isOnline'] ?? false,
          university: u['university'],
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  List<MapEventPin> _parseEventPins(dynamic response, double lat, double lng) {
    if (response == null) return [];
    try {
      final data = response.data;
      final raw = data is Map
          ? (data['data']?['events'] ?? data['data'] ?? [])
          : [];
      final list = raw as List;
      return list.asMap().entries.map((entry) {
        final i = entry.key;
        final e = entry.value;
        final loc = e['location'];
        return MapEventPin(
          id: e['id'] ?? 'event_$i',
          title: e['title'] ?? 'Event',
          coverImageUrl: e['coverImageUrl'],
          category: EventCategory.fromString(e['category'] ?? 'OTHER'),
          position: LatLng(
            (loc?['latitude'] as num?)?.toDouble() ?? lat,
            (loc?['longitude'] as num?)?.toDouble() ?? lng,
          ),
          startDate: DateTime.tryParse(e['startDate'] ?? '') ?? DateTime.now().add(Duration(hours: i + 2)),
          attendeeCount: e['attendeeCount'] ?? 0,
          isFree: e['isFree'] ?? true,
          price: (e['price'] as num?)?.toDouble(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  void setFilter(MapFilter filter) {
    state = state.copyWith(filter: filter);
  }

  void togglePoiCategory(PoiCategory cat) {
    final current = Set<PoiCategory>.from(state.activePoiFilters);
    if (current.contains(cat)) {
      current.remove(cat);
    } else {
      current.add(cat);
    }
    state = state.copyWith(activePoiFilters: current);
  }

  void clearPoiFilters() {
    state = state.copyWith(activePoiFilters: const {});
  }

  void toggleShowPois() {
    state = state.copyWith(showPois: !state.showPois);
  }

  Future<void> relocate() async {
    state = state.copyWith(isLocating: true);
    await _requestLocationAndLoad();
  }

  /// Fetch walking directions from Mapbox Directions API
  Future<void> fetchDirections(LatLng destination, String destinationName) async {
    if (state.userLocation == null) return;

    state = state.copyWith(isLoadingRoute: true);

    try {
      final origin = state.userLocation!;
      final url = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/walking/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?geometries=geojson&overview=full&access_token=${AppConfig.mapboxAccessToken}',
      );

      final response = await http.get(url);

      if (response.statusCode != 200) {
        debugPrint('[Map] Directions API error: ${response.statusCode}');
        state = state.copyWith(isLoadingRoute: false);
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = json['routes'] as List?;

      if (routes == null || routes.isEmpty) {
        debugPrint('[Map] No routes found');
        state = state.copyWith(isLoadingRoute: false);
        return;
      }

      final route = routes[0] as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      final distance = (route['distance'] as num).toDouble();
      final duration = (route['duration'] as num).toDouble();

      // Convert [lng, lat] pairs to LatLng
      final points = coordinates.map<LatLng>((coord) {
        final c = coord as List;
        return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
      }).toList();

      state = state.copyWith(
        activeRoute: MapRouteInfo(
          polylinePoints: points,
          distanceMeters: distance,
          durationSeconds: duration,
          destination: destination,
          destinationName: destinationName,
        ),
        isLoadingRoute: false,
      );
    } catch (e) {
      debugPrint('[Map] Directions error: $e');
      state = state.copyWith(isLoadingRoute: false);
    }
  }

  /// Clear the active route
  void clearRoute() {
    state = state.copyWith(clearRoute: true);
  }
}

final snapMapProvider = StateNotifierProvider<SnapMapNotifier, SnapMapState>(
  (ref) => SnapMapNotifier(ApiService()),
);
