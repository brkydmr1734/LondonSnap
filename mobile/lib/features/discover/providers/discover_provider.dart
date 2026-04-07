import 'dart:async';
import 'package:flutter/material.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/core/errors/app_exceptions.dart';
import 'package:londonsnaps/core/errors/error_handler.dart';
import 'package:londonsnaps/features/discover/models/discover_models.dart';

class DiscoverProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<DiscoverEvent> _events = [];
  List<NearbyUser> _nearbyUsers = [];
  List<MatchProfile> _matches = [];
  DiscoverEvent? _selectedEvent;
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  Timer? _searchDebounce;
  EventCategory? _selectedCategory;
  List<dynamic> _searchResults = [];

  List<DiscoverEvent> get events => _events;
  List<NearbyUser> get nearbyUsers => _nearbyUsers;
  List<MatchProfile> get matches => _matches;
  DiscoverEvent? get selectedEvent => _selectedEvent;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  EventCategory? get selectedCategory => _selectedCategory;
  List<dynamic> get searchResults => _searchResults;

  Future<void> loadDiscoverFeed() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await _api.getDiscoverFeed();
      final data = response.data['data'];
      if (data['events'] != null) {
        _events = (data['events'] as List).map((e) => DiscoverEvent.fromJson(e)).toList();
      }
      if (data['nearbyUsers'] != null) {
        _nearbyUsers = (data['nearbyUsers'] as List).map((u) => NearbyUser.fromJson(u)).toList();
      }
      if (data['matches'] != null) {
        _matches = (data['matches'] as List).map((m) => MatchProfile.fromJson(m)).toList();
      }
    } catch (e) {
      _error = _handleError(e);
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadEvents({String? category}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.getEvents(category: category);
      final data = response.data['data'];
      final eventsList = data['events'] as List? ?? data as List? ?? [];
      _events = eventsList.map((e) => DiscoverEvent.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      _error = _handleError(e);
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadEventDetail(String eventId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.getEventDetail(eventId);
      final data = response.data['data'];
      final eventData = data['event'] ?? data;
      _selectedEvent = DiscoverEvent.fromJson(eventData);
    } catch (e) {
      _error = _handleError(e);
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadNearbyUsers({required double lat, required double lng}) async {
    try {
      final response = await _api.getNearbyUsers(lat: lat, lng: lng);
      final data = response.data['data'];
      final usersList = data['users'] as List? ?? data as List? ?? [];
      _nearbyUsers = usersList.map((u) => NearbyUser.fromJson(u as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  Future<void> loadMatches() async {
    try {
      final response = await _api.getMatches();
      final data = response.data['data'];
      // Backend returns {received: [...], sent: [...]}
      final received = data['received'] as List? ?? [];
      final sent = data['sent'] as List? ?? [];
      _matches = [...received, ...sent].map((m) => MatchProfile.fromJson(m as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  Future<void> attendEvent(String eventId) async {
    try {
      await _api.attendEvent(eventId);
      await loadEvents();
      if (_selectedEvent?.id == eventId) await loadEventDetail(eventId);
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  Future<void> cancelAttendance(String eventId) async {
    try {
      await _api.cancelAttendance(eventId);
      if (_selectedEvent?.id == eventId) await loadEventDetail(eventId);
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 500), () => _performSearch(query));
  }

  Future<void> _performSearch(String query) async {
    try {
      final response = await _api.searchDiscover(query);
      final data = response.data['data'];
      // Backend returns {users: [...], events: [...]}
      final users = data['users'] as List? ?? [];
      final events = data['events'] as List? ?? [];
      _searchResults = [...users, ...events];
      notifyListeners();
    } catch (e) {
      _error = _handleError(e);
      notifyListeners();
    }
  }

  void setSelectedCategory(EventCategory? category) {
    _selectedCategory = category;
    notifyListeners();
    loadEvents(category: category?.value);
  }

  String _handleError(dynamic e) {
    final ex = e is AppException ? e : ErrorHandler.handle(e);
    return ex.message;
  }
}
