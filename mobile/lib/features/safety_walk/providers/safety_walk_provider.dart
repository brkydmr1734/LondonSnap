import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/core/errors/app_exceptions.dart';
import 'package:londonsnaps/core/errors/error_handler.dart';
import 'package:londonsnaps/features/safety_walk/models/safety_walk_models.dart';

class SafetyWalkProvider extends ChangeNotifier {
  static final SafetyWalkProvider _instance = SafetyWalkProvider._internal();
  factory SafetyWalkProvider() => _instance;
  SafetyWalkProvider._internal();

  final ApiService _api = ApiService();

  // State
  SafetyWalk? _activeWalk;
  List<SafetyWalkCompanion> _companions = [];
  List<RouteOption> _routeOptions = [];
  List<NearbyStop> _nearbyStops = [];
  RouteOption? _selectedRoute;
  SafetyScore? _safetyScore;
  Map<String, SafetyWalkLocation> _latestLocations = {};
  List<SafetyWalk> _walkHistory = [];
  int _historyTotal = 0;
  bool _isSearching = false;
  bool _isLoading = false;
  bool _sosActive = false;
  String? _error;
  Timer? _locationTimer;
  StreamSubscription<Position>? _positionSubscription;

  // Getters
  SafetyWalk? get activeWalk => _activeWalk;
  List<SafetyWalkCompanion> get companions => _companions;
  List<RouteOption> get routeOptions => _routeOptions;
  List<NearbyStop> get nearbyStops => _nearbyStops;
  RouteOption? get selectedRoute => _selectedRoute;
  SafetyScore? get safetyScore => _safetyScore;
  Map<String, SafetyWalkLocation> get latestLocations => _latestLocations;
  List<SafetyWalk> get walkHistory => _walkHistory;
  int get historyTotal => _historyTotal;
  bool get isSearching => _isSearching;
  bool get isLoading => _isLoading;
  bool get sosActive => _sosActive;
  String? get error => _error;
  bool get hasActiveWalk => _activeWalk != null;
  bool get isWalkActive => _activeWalk?.status == SafetyWalkStatus.active;
  bool get isWalkPending => _activeWalk?.status == SafetyWalkStatus.pending;
  bool get isWalkAccepted => _activeWalk?.status == SafetyWalkStatus.accepted;

  /// Find potential companions for a safety walk
  Future<void> findCompanions(
    double startLat,
    double startLng,
    double endLat,
    double endLng, {
    int radius = 2000,
  }) async {
    _isSearching = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.findSafetyCompanions({
        'startLat': startLat,
        'startLng': startLng,
        'endLat': endLat,
        'endLng': endLng,
        'radius': radius,
      });

      final companionsList = response.data['data']['companions'] as List? ?? [];
      _companions = companionsList
          .map((c) => SafetyWalkCompanion.fromJson(c as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = _handleError(e);
    }

    _isSearching = false;
    notifyListeners();
  }

  /// Get route options from TfL / Mapbox
  Future<void> getRouteOptions(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng, {
    String mode = 'mixed',
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.getRouteOptions({
        'fromLat': fromLat,
        'fromLng': fromLng,
        'toLat': toLat,
        'toLng': toLng,
        'mode': mode,
      });

      final routesList = response.data['data']['routes'] as List? ?? [];
      _routeOptions = routesList
          .map((r) => RouteOption.fromJson(r as Map<String, dynamic>))
          .toList();

      // Auto-select first route if available
      if (_routeOptions.isNotEmpty && _selectedRoute == null) {
        _selectedRoute = _routeOptions.first;
      }
    } catch (e) {
      _error = _handleError(e);
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Get nearby transport stops
  Future<void> getNearbyStops(double lat, double lng, {int radius = 500}) async {
    try {
      final response = await _api.getNearbyStops({
        'lat': lat,
        'lng': lng,
        'radius': radius,
      });

      final stopsList = response.data['data']['stops'] as List? ?? [];
      _nearbyStops = stopsList
          .map((s) => NearbyStop.fromJson(s as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  /// Select a route option
  void selectRoute(RouteOption route) {
    _selectedRoute = route;
    notifyListeners();
  }

  /// Clear selected route
  void clearSelectedRoute() {
    _selectedRoute = null;
    notifyListeners();
  }

  /// Request a safety walk with a companion
  Future<bool> requestWalk(String companionId) async {
    if (_selectedRoute == null) {
      _error = 'Please select a route first';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final routePoints = _selectedRoute!.polylinePoints;
      final response = await _api.requestSafetyWalk({
        'companionId': companionId,
        'startLat': routePoints.isNotEmpty ? routePoints.first['lat'] : 0,
        'startLng': routePoints.isNotEmpty ? routePoints.first['lng'] : 0,
        'endLat': routePoints.isNotEmpty ? routePoints.last['lat'] : 0,
        'endLng': routePoints.isNotEmpty ? routePoints.last['lng'] : 0,
        'routePolyline': routePoints,
        'estimatedDuration': _selectedRoute!.duration,
        'transportMode': _selectedRoute!.mode.toUpperCase(),
      });

      final walkData = response.data['data']['walk'];
      if (walkData != null) {
        _activeWalk = SafetyWalk.fromJson(walkData as Map<String, dynamic>);
        _startStatusPolling();
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _handleError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Accept a walk request (as companion)
  Future<bool> acceptWalk(String walkId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.acceptSafetyWalk(walkId);
      final walkData = response.data['data']['walk'];
      if (walkData != null) {
        _activeWalk = SafetyWalk.fromJson(walkData as Map<String, dynamic>);
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _handleError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Decline a walk request (as companion)
  Future<bool> declineWalk(String walkId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _api.declineSafetyWalk(walkId);
      if (_activeWalk?.id == walkId) {
        _activeWalk = null;
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _handleError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Start the walk (after companion arrives)
  Future<bool> startWalk() async {
    if (_activeWalk == null) {
      _error = 'No active walk to start';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.startSafetyWalk(_activeWalk!.id);
      final walkData = response.data['data']['walk'];
      if (walkData != null) {
        _activeWalk = SafetyWalk.fromJson(walkData as Map<String, dynamic>);
      }

      // Start location tracking
      _startLocationTracking();

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _handleError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Start location tracking during active walk
  void _startLocationTracking() {
    _stopLocationTracking();

    // Check permissions first
    _checkLocationPermission().then((hasPermission) {
      if (!hasPermission) {
        debugPrint('[SafetyWalk] No location permission');
        return;
      }

      // Start position stream
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update every 10 meters
        ),
      ).listen(
        (Position position) {
          _sendLocationUpdate(position);
        },
        onError: (e) {
          debugPrint('[SafetyWalk] Location stream error: $e');
          _stopLocationTracking();
        },
      );

      // Also update every 10 seconds regardless of movement
      _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );
          _sendLocationUpdate(position);
        } catch (e) {
          debugPrint('[SafetyWalk] Failed to get position: $e');
        }
      });
    });
  }

  /// Check and request location permission
  Future<bool> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Send location update to server
  Future<void> _sendLocationUpdate(Position position) async {
    if (_activeWalk == null || _activeWalk!.status != SafetyWalkStatus.active) {
      return;
    }

    try {
      final response = await _api.updateWalkLocation(_activeWalk!.id, {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'speed': position.speed,
        'heading': position.heading,
      });

      // Update companion distance if returned
      final data = response.data['data'];
      if (data != null && data['companionDistance'] != null) {
        debugPrint('[SafetyWalk] Companion distance: ${data['companionDistance']}m');
      }
    } catch (e) {
      debugPrint('[SafetyWalk] Failed to send location: $e');
    }
  }

  /// Stop location tracking
  void _stopLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Poll for status changes (when waiting for companion response)
  Timer? _statusPollingTimer;
  
  void _startStatusPolling() {
    _stopStatusPolling();
    _statusPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await loadActiveWalk();
      // Stop polling once walk is active or cancelled
      if (_activeWalk == null ||
          _activeWalk!.status == SafetyWalkStatus.active ||
          _activeWalk!.status == SafetyWalkStatus.cancelled ||
          _activeWalk!.status == SafetyWalkStatus.completed ||
          _activeWalk!.status == SafetyWalkStatus.sosTriggered) {
        _stopStatusPolling();
      }
    });
  }

  void _stopStatusPolling() {
    _statusPollingTimer?.cancel();
    _statusPollingTimer = null;
  }

  /// Trigger SOS emergency
  Future<bool> triggerSOS() async {
    if (_activeWalk == null) {
      _error = 'No active walk for SOS';
      notifyListeners();
      return false;
    }

    try {
      final response = await _api.triggerSOS(_activeWalk!.id);
      _sosActive = true;
      
      // Vibrate device for haptic feedback
      HapticFeedback.vibrate();

      final data = response.data['data'];
      if (data != null) {
        final result = SOSResult.fromJson(data as Map<String, dynamic>);
        debugPrint('[SafetyWalk] SOS triggered, ${result.emergencyContacts} contacts notified');
      }

      // Update local walk state
      _activeWalk = _activeWalk!.copyWith(
        status: SafetyWalkStatus.sosTriggered,
        sosTriggered: true,
      );

      notifyListeners();
      return true;
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
      return false;
    }
  }

  /// Complete the walk
  Future<bool> completeWalk() async {
    if (_activeWalk == null) {
      _error = 'No active walk to complete';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.completeSafetyWalk(_activeWalk!.id);
      _stopLocationTracking();

      final data = response.data['data'];
      if (data != null) {
        final walkData = data['walk'];
        if (walkData != null) {
          _activeWalk = SafetyWalk.fromJson(walkData as Map<String, dynamic>);
        }
      }

      _sosActive = false;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _handleError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Cancel the walk
  Future<bool> cancelWalk() async {
    if (_activeWalk == null) {
      _error = 'No active walk to cancel';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _api.cancelSafetyWalk(_activeWalk!.id);
      _stopLocationTracking();
      _stopStatusPolling();
      _activeWalk = null;
      _sosActive = false;

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _handleError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Rate companion after walk completion
  /// [walkId] can be provided for rating from history (when no active walk)
  Future<bool> rateCompanion(String ratedId, int score, {String? comment, String? walkId}) async {
    final targetWalkId = walkId ?? _activeWalk?.id;
    if (targetWalkId == null) {
      _error = 'No walk to rate';
      notifyListeners();
      return false;
    }

    try {
      await _api.rateSafetyWalkCompanion(targetWalkId, {
        'ratedId': ratedId,
        'score': score,
        'comment': comment,
      });

      // Clear active walk after rating (only if it matches)
      if (_activeWalk?.id == targetWalkId) {
        _activeWalk = null;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
      return false;
    }
  }

  /// Load current active walk
  Future<void> loadActiveWalk() async {
    try {
      final response = await _api.getActiveWalk();
      final walkData = response.data['data']['walk'];
      
      if (walkData != null) {
        _activeWalk = SafetyWalk.fromJson(walkData as Map<String, dynamic>);
        
        // Resume location tracking if walk is active
        if (_activeWalk!.status == SafetyWalkStatus.active) {
          _startLocationTracking();
        }
        
        // Parse location updates if available
        final locations = walkData['locationUpdates'] as List?;
        if (locations != null && locations.isNotEmpty) {
          for (final loc in locations) {
            final locData = loc as Map<String, dynamic>;
            final userId = locData['userId'] as String?;
            if (userId != null) {
              _latestLocations[userId] = SafetyWalkLocation.fromJson(locData);
            }
          }
        }
      } else {
        _activeWalk = null;
        _stopLocationTracking();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[SafetyWalk] loadActiveWalk error: $e');
      // Don't set error for polling failures
    }
  }

  /// Load user's safety score
  Future<void> loadSafetyScore() async {
    try {
      final response = await _api.getSafetyScore();
      final scoreData = response.data['data']['safetyScore'];
      if (scoreData != null) {
        _safetyScore = SafetyScore.fromJson(scoreData as Map<String, dynamic>);
        notifyListeners();
      }
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  /// Load walk history
  Future<void> loadHistory({int limit = 20, int offset = 0}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.getWalkHistory(limit: limit, offset: offset);
      final data = response.data['data'];
      
      final walksList = data['walks'] as List? ?? [];
      final walks = walksList
          .map((w) => SafetyWalk.fromJson(w as Map<String, dynamic>))
          .toList();

      if (offset == 0) {
        _walkHistory = walks;
      } else {
        _walkHistory.addAll(walks);
      }
      
      _historyTotal = data['total'] ?? walks.length;
    } catch (e) {
      _error = _handleError(e);
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Clear companions list
  void clearCompanions() {
    _companions = [];
    notifyListeners();
  }

  /// Clear route options
  void clearRouteOptions() {
    _routeOptions = [];
    _selectedRoute = null;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Clear active walk (after completion/cancellation shown)
  void clearActiveWalk() {
    _activeWalk = null;
    _sosActive = false;
    notifyListeners();
  }

  /// Reset all state
  void reset() {
    _stopLocationTracking();
    _stopStatusPolling();
    _activeWalk = null;
    _companions = [];
    _routeOptions = [];
    _nearbyStops = [];
    _selectedRoute = null;
    _latestLocations = {};
    _sosActive = false;
    _error = null;
    notifyListeners();
  }

  String _handleError(dynamic e) {
    final ex = e is AppException ? e : ErrorHandler.handle(e);
    return ex.message;
  }

  @override
  void dispose() {
    _stopLocationTracking();
    _stopStatusPolling();
    super.dispose();
  }
}
