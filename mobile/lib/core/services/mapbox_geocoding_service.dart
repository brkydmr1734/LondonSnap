import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:londonsnaps/core/config/app_config.dart';

/// Mapbox Geocoding + Search Box API service for comprehensive place search.
/// Uses dual APIs: Search Box API for rich POI data, Geocoding v5 for addresses.
/// Covers streets, addresses, businesses, restaurants, nightclubs, venues, etc.
class MapboxGeocodingService {
  static const _token = AppConfig.mapboxAccessToken;

  // Mapbox Geocoding v5 (addresses, places)
  static const _geocodeUrl =
      'https://api.mapbox.com/geocoding/v5/mapbox.places';

  // Mapbox Search Box API v1 (rich POI / business data)
  static const _searchBoxUrl =
      'https://api.mapbox.com/search/searchbox/v1';

  /// Default proximity: central London
  static const _defaultLat = 51.5074;
  static const _defaultLng = -0.1278;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  Timer? _debounceTimer;
  String _sessionToken = _generateSessionToken();

  static String _generateSessionToken() {
    final r = Random();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// Comprehensive search: merges Search Box API (POIs) + Geocoding v5 (addresses).
  /// Returns up to 10 results with rich business/venue data.
  Future<List<GeocodingResult>> search(
    String query, {
    double? proximityLat,
    double? proximityLng,
    int limit = 12,
  }) async {
    if (query.trim().length < 2) return [];

    final lat = proximityLat ?? _defaultLat;
    final lng = proximityLng ?? _defaultLng;

    try {
      // Check if query looks like a UK postcode — include postcodes.io lookup
      final postcodeFuture = _isUkPostcode(query)
          ? _postcodeIoLookup(query)
          : Future.value(<GeocodingResult>[]);

      // Fetch from all APIs in parallel for maximum coverage
      final results = await Future.wait([
        _searchBoxSuggestAndRetrieve(query, lat, lng, limit: 8),
        _geocodeSearch(query, lat, lng, limit: 6),
        postcodeFuture,
      ]);

      final searchBoxResults = results[0];
      final geocodeResults = results[1];
      final postcodeResults = results[2];

      // Merge: postcode.io first (exact match), then search box, then geocode
      final merged = <GeocodingResult>[];
      final seenIds = <String>{};

      // Exact postcode matches first
      for (final r in postcodeResults) {
        if (seenIds.add(r.id)) merged.add(r);
      }
      for (final r in searchBoxResults) {
        if (seenIds.add(r.id)) merged.add(r);
      }
      for (final r in geocodeResults) {
        // Deduplicate by proximity (within ~50m = same place)
        final isDupe = merged.any((m) =>
            (m.latitude - r.latitude).abs() < 0.0005 &&
            (m.longitude - r.longitude).abs() < 0.0005 &&
            m.name.toLowerCase() == r.name.toLowerCase());
        if (!isDupe && seenIds.add(r.id)) merged.add(r);
      }

      return merged.take(limit).toList();
    } catch (e) {
      debugPrint('[Geocoding] Combined search error: $e');
      // Fallback to geocode only
      return _geocodeSearch(query, lat, lng, limit: limit);
    }
  }

  /// Search Box API: suggest → retrieve (rich POI data)
  Future<List<GeocodingResult>> _searchBoxSuggestAndRetrieve(
    String query, double lat, double lng, {int limit = 7}
  ) async {
    try {
      final encodedQuery = Uri.encodeComponent(query.trim());
      final suggestUrl =
          '$_searchBoxUrl/suggest'
          '?q=$encodedQuery'
          '&access_token=$_token'
          '&session_token=$_sessionToken'
          '&proximity=$lng,$lat'
          '&limit=$limit'
          '&language=en'
          '&country=gb'
          '&types=poi,address,street,place,neighborhood,postcode';

      final suggestResponse = await _dio.get(suggestUrl);

      if (suggestResponse.statusCode != 200 || suggestResponse.data == null) {
        return [];
      }

      final suggestions = suggestResponse.data['suggestions'] as List? ?? [];
      if (suggestions.isEmpty) return [];

      // Retrieve full details for all suggestions in parallel
      final retrieveFutures = suggestions.map((suggestion) async {
        final mapboxId = suggestion['mapbox_id'] as String?;
        if (mapboxId == null) return null;

        try {
          final retrieveUrl =
              '$_searchBoxUrl/retrieve/$mapboxId'
              '?access_token=$_token'
              '&session_token=$_sessionToken';

          final retrieveResponse = await _dio.get(retrieveUrl);

          if (retrieveResponse.statusCode == 200 &&
              retrieveResponse.data != null) {
            final features =
                retrieveResponse.data['features'] as List? ?? [];
            if (features.isNotEmpty) {
              return GeocodingResult.fromSearchBox(
                features.first as Map<String, dynamic>,
                suggestion as Map<String, dynamic>,
              );
            }
          }
        } catch (e) {
          debugPrint('[Geocoding] Retrieve failed for $mapboxId: $e');
        }
        // Fallback: build from suggestion name + address (no coordinates)
        return GeocodingResult._fromSuggestionOnly(
          suggestion as Map<String, dynamic>,
        );
      }).toList();

      final retrieved = await Future.wait(retrieveFutures);
      final results = retrieved.whereType<GeocodingResult>()
          .where((r) => r.latitude != 0.0 || r.longitude != 0.0)
          .toList();

      // Rotate session token after a full suggest+retrieve cycle
      _sessionToken = _generateSessionToken();
      return results;
    } catch (e) {
      debugPrint('[Geocoding] Search Box API error: $e');
      return [];
    }
  }

  /// Geocoding v5: address/place search (good for streets, postcodes, areas)
  Future<List<GeocodingResult>> _geocodeSearch(
    String query, double lat, double lng, {int limit = 5}
  ) async {
    try {
      final encodedQuery = Uri.encodeComponent(query.trim());
      final url =
          '$_geocodeUrl/$encodedQuery.json'
          '?access_token=$_token'
          '&proximity=$lng,$lat'
          '&limit=$limit'
          '&types=poi,address,place,locality,neighborhood,postcode'
          '&language=en'
          '&fuzzyMatch=true';

      final response = await _dio.get(url);

      if (response.statusCode == 200 && response.data != null) {
        final features = response.data['features'] as List? ?? [];
        return features
            .map((f) => GeocodingResult.fromMapbox(f as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[Geocoding] Geocode v5 error: $e');
    }
    return [];
  }

  /// Debounced search - cancels previous request if new one comes in.
  /// Use this for real-time typing autocomplete.
  void searchDebounced(
    String query, {
    double? proximityLat,
    double? proximityLng,
    required void Function(List<GeocodingResult> results) onResults,
    Duration debounce = const Duration(milliseconds: 300),
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () async {
      final results = await search(
        query,
        proximityLat: proximityLat,
        proximityLng: proximityLng,
      );
      onResults(results);
    });
  }

  /// Reverse geocode: get address from coordinates.
  Future<GeocodingResult?> reverseGeocode(double lat, double lng) async {
    try {
      // Try Search Box reverse first (richer data)
      final searchUrl =
          '$_searchBoxUrl/reverse'
          '?access_token=$_token'
          '&longitude=$lng'
          '&latitude=$lat'
          '&limit=1'
          '&language=en'
          '&types=poi,address,place,street';

      final searchResp = await _dio.get(searchUrl);

      if (searchResp.statusCode == 200 && searchResp.data != null) {
        final features = searchResp.data['features'] as List? ?? [];
        if (features.isNotEmpty) {
          final feature = features.first as Map<String, dynamic>;
          final props = feature['properties'] as Map<String, dynamic>? ?? {};
          final coords = feature['geometry']?['coordinates'] as List?;
          if (coords != null && coords.length >= 2) {
            return GeocodingResult(
              id: props['mapbox_id'] as String? ?? 'reverse',
              name: props['name'] as String? ?? props['full_address'] as String? ?? 'Unknown',
              address: props['place_formatted'] as String? ?? props['full_address'] as String?,
              category: (props['poi_category'] as List?)?.firstOrNull?.toString(),
              latitude: (coords[1] as num).toDouble(),
              longitude: (coords[0] as num).toDouble(),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[Geocoding] Search Box reverse error: $e');
    }

    // Fallback to v5 geocoding
    try {
      final url =
          '$_geocodeUrl/$lng,$lat.json'
          '?access_token=$_token'
          '&limit=1'
          '&types=poi,address,place'
          '&language=en';

      final response = await _dio.get(url);

      if (response.statusCode == 200 && response.data != null) {
        final features = response.data['features'] as List? ?? [];
        if (features.isNotEmpty) {
          return GeocodingResult.fromMapbox(
              features.first as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('[Geocoding] Geocode v5 reverse error: $e');
    }
    return null;
  }

  void dispose() {
    _debounceTimer?.cancel();
  }

  // ── UK Postcode support via postcodes.io (free, 100% coverage) ──

  /// UK postcode regex: A1 1AA, A11 1AA, AA1 1AA, AA11 1AA, etc.
  static final _ukPostcodeRegex = RegExp(
    r'^[A-Z]{1,2}[0-9][0-9A-Z]?\s*[0-9][A-Z]{2}$',
    caseSensitive: false,
  );

  /// Also match partial postcodes like "E14" or "SW1A"
  static final _ukPartialPostcodeRegex = RegExp(
    r'^[A-Z]{1,2}[0-9][0-9A-Z]?$',
    caseSensitive: false,
  );

  bool _isUkPostcode(String query) {
    final q = query.trim();
    return _ukPostcodeRegex.hasMatch(q) || _ukPartialPostcodeRegex.hasMatch(q);
  }

  /// Look up a UK postcode using postcodes.io (free API, no key needed)
  Future<List<GeocodingResult>> _postcodeIoLookup(String query) async {
    final q = query.trim().replaceAll(' ', '');
    try {
      // Try exact lookup first
      final url = 'https://api.postcodes.io/postcodes/$q';
      final response = await _dio.get(url);

      if (response.statusCode == 200 && response.data != null) {
        final result = response.data['result'];
        if (result != null) {
          final postcode = result['postcode'] as String? ?? q;
          final lat = (result['latitude'] as num?)?.toDouble() ?? 0.0;
          final lng = (result['longitude'] as num?)?.toDouble() ?? 0.0;
          final ward = result['admin_ward'] as String? ?? '';
          final district = result['admin_district'] as String? ?? '';
          final region = result['region'] as String? ?? '';

          final addressParts = [ward, district, region]
              .where((p) => p.isNotEmpty)
              .toList();

          return [
            GeocodingResult(
              id: 'postcode_$postcode',
              name: postcode,
              address: addressParts.join(', '),
              category: 'postcode',
              latitude: lat,
              longitude: lng,
            ),
          ];
        }
      }

      // If exact lookup fails, try autocomplete
      final autoUrl = 'https://api.postcodes.io/postcodes/$q/autocomplete';
      final autoResponse = await _dio.get(autoUrl);

      if (autoResponse.statusCode == 200 && autoResponse.data != null) {
        final results = autoResponse.data['result'] as List? ?? [];
        if (results.isEmpty) return [];

        // Look up first 3 autocomplete matches
        final lookups = <GeocodingResult>[];
        for (final pc in results.take(3)) {
          final pcStr = pc.toString().replaceAll(' ', '');
          try {
            final pcUrl = 'https://api.postcodes.io/postcodes/$pcStr';
            final pcResp = await _dio.get(pcUrl);
            if (pcResp.statusCode == 200 && pcResp.data?['result'] != null) {
              final r = pcResp.data['result'];
              final ward = r['admin_ward'] as String? ?? '';
              final district = r['admin_district'] as String? ?? '';
              final addressParts = [ward, district]
                  .where((p) => p.isNotEmpty)
                  .toList();
              lookups.add(GeocodingResult(
                id: 'postcode_${r['postcode']}',
                name: r['postcode'] as String? ?? pcStr,
                address: addressParts.join(', '),
                category: 'postcode',
                latitude: (r['latitude'] as num?)?.toDouble() ?? 0.0,
                longitude: (r['longitude'] as num?)?.toDouble() ?? 0.0,
              ));
            }
          } catch (_) {}
        }
        return lookups;
      }
    } catch (e) {
      debugPrint('[Geocoding] postcodes.io error: $e');
    }
    return [];
  }
}

/// A geocoding search result.
class GeocodingResult {
  final String id;
  final String name;
  final String? address;
  final String? category;
  final double latitude;
  final double longitude;

  GeocodingResult({
    required this.id,
    required this.name,
    this.address,
    this.category,
    required this.latitude,
    required this.longitude,
  });

  factory GeocodingResult.fromMapbox(Map<String, dynamic> feature) {
    final center = feature['center'] as List? ?? [0.0, 0.0];
    final properties = feature['properties'] as Map<String, dynamic>? ?? {};

    // Extract category from properties or context
    String? category;
    if (properties['category'] != null) {
      category = (properties['category'] as String)
          .split(',')
          .first
          .trim();
    }

    // Build address from context
    String? address;
    final context = feature['context'] as List?;
    if (context != null && context.isNotEmpty) {
      final parts = <String>[];
      for (final ctx in context) {
        if (ctx is Map) {
          final ctxId = ctx['id'] as String? ?? '';
          final text = ctx['text'] as String? ?? '';
          if (ctxId.startsWith('neighborhood') ||
              ctxId.startsWith('locality') ||
              ctxId.startsWith('place') ||
              ctxId.startsWith('postcode')) {
            parts.add(text);
          }
        }
      }
      if (parts.isNotEmpty) {
        address = parts.join(', ');
      }
    }

    // Fallback address from place_name
    address ??= _extractAddress(feature['place_name'] as String? ?? '');

    return GeocodingResult(
      id: feature['id'] as String? ?? '',
      name: feature['text'] as String? ?? 'Unknown',
      address: address,
      category: category,
      latitude: (center[1] as num).toDouble(),
      longitude: (center[0] as num).toDouble(),
    );
  }

  /// Parse Search Box API retrieve response (richer POI data)
  factory GeocodingResult.fromSearchBox(
    Map<String, dynamic> feature,
    Map<String, dynamic> suggestion,
  ) {
    final props = feature['properties'] as Map<String, dynamic>? ?? {};
    final coords = feature['geometry']?['coordinates'] as List?;

    // Category from Search Box
    String? category;
    final poiCats = props['poi_category'] as List?;
    final poiCatIds = props['poi_category_ids'] as List?;
    if (poiCats != null && poiCats.isNotEmpty) {
      category = poiCats.first.toString();
    } else if (poiCatIds != null && poiCatIds.isNotEmpty) {
      category = poiCatIds.first.toString();
    }

    // Address from Search Box
    String? address = props['place_formatted'] as String?;
    address ??= props['full_address'] as String?;
    address ??= props['address'] as String?;

    // Name
    String name = props['name'] as String? ??
        suggestion['name'] as String? ??
        'Unknown';

    return GeocodingResult(
      id: props['mapbox_id'] as String? ?? suggestion['mapbox_id'] as String? ?? '',
      name: name,
      address: address,
      category: category,
      latitude: coords != null && coords.length >= 2
          ? (coords[1] as num).toDouble()
          : 0.0,
      longitude: coords != null && coords.length >= 2
          ? (coords[0] as num).toDouble()
          : 0.0,
    );
  }

  /// Fallback: build from suggestion data only (when retrieve fails)
  factory GeocodingResult._fromSuggestionOnly(Map<String, dynamic> suggestion) {
    String? category;
    final poiCats = suggestion['poi_category'] as List?;
    if (poiCats != null && poiCats.isNotEmpty) {
      category = poiCats.first.toString();
    }

    return GeocodingResult(
      id: suggestion['mapbox_id'] as String? ?? '',
      name: suggestion['name'] as String? ?? 'Unknown',
      address: suggestion['place_formatted'] as String? ??
          suggestion['full_address'] as String?,
      category: category,
      latitude: 0.0,
      longitude: 0.0,
    );
  }

  /// Extract a short address from the full place_name
  /// e.g. "UCL, Gower Street, London, WC1E 6BT" → "Gower Street, London"
  static String? _extractAddress(String placeName) {
    final parts = placeName.split(',').map((p) => p.trim()).toList();
    if (parts.length > 1) {
      // Skip the first part (it's the place name itself)
      // Take next 2 parts as address
      final addressParts = parts.sublist(1).take(2).toList();
      return addressParts.join(', ');
    }
    return null;
  }

  /// Icon hint based on category
  String get categoryIcon {
    if (category == null) return '📍';
    final cat = category!.toLowerCase();
    if (cat.contains('restaurant') || cat.contains('food') || cat.contains('diner')) return '🍽️';
    if (cat.contains('cafe') || cat.contains('coffee') || cat.contains('bakery')) return '☕';
    if (cat.contains('nightclub') || cat.contains('night club') || cat.contains('club') || cat.contains('lounge') || cat.contains('disco')) return '🪩';
    if (cat.contains('bar') || cat.contains('pub') || cat.contains('cocktail') || cat.contains('wine')) return '🍸';
    if (cat.contains('casino') || cat.contains('gambling') || cat.contains('betting')) return '🎰';
    if (cat.contains('hotel') || cat.contains('lodging') || cat.contains('hostel') || cat.contains('motel')) return '🏨';
    if (cat.contains('hospital') || cat.contains('medical') || cat.contains('clinic') || cat.contains('pharmacy') || cat.contains('dentist')) return '🏥';
    if (cat.contains('university') || cat.contains('school') || cat.contains('college') || cat.contains('education') || cat.contains('library')) return '🎓';
    if (cat.contains('station') || cat.contains('rail') || cat.contains('transit') || cat.contains('airport') || cat.contains('terminal')) return '🚂';
    if (cat.contains('park') || cat.contains('garden') || cat.contains('playground') || cat.contains('recreation')) return '🌳';
    if (cat.contains('shop') || cat.contains('store') || cat.contains('mall') || cat.contains('supermarket') || cat.contains('market') || cat.contains('retail')) return '🛍️';
    if (cat.contains('museum') || cat.contains('gallery') || cat.contains('art') || cat.contains('exhibit')) return '🏛️';
    if (cat.contains('gym') || cat.contains('sport') || cat.contains('fitness') || cat.contains('stadium') || cat.contains('arena')) return '🏋️';
    if (cat.contains('cinema') || cat.contains('theater') || cat.contains('theatre') || cat.contains('concert') || cat.contains('entertainment') || cat.contains('show')) return '🎭';
    if (cat.contains('bank') || cat.contains('atm') || cat.contains('finance')) return '🏦';
    if (cat.contains('gas') || cat.contains('fuel') || cat.contains('petrol') || cat.contains('charging')) return '⛽';
    if (cat.contains('mosque') || cat.contains('church') || cat.contains('temple') || cat.contains('synagogue') || cat.contains('worship')) return '🕌';
    if (cat.contains('spa') || cat.contains('salon') || cat.contains('beauty') || cat.contains('hair')) return '💆';
    if (cat.contains('parking') || cat.contains('garage')) return '🅿️';
    if (cat.contains('police') || cat.contains('fire')) return '🚨';
    if (cat.contains('office') || cat.contains('coworking') || cat.contains('business')) return '🏢';
    if (cat.contains('postcode') || cat.contains('postal')) return '📮';
    return '📍';
  }

  /// Human-readable category label
  String? get categoryLabel {
    if (category == null) return null;
    final cat = category!.toLowerCase();
    if (cat.contains('restaurant') || cat.contains('food') || cat.contains('diner')) return 'Restaurant';
    if (cat.contains('cafe') || cat.contains('coffee')) return 'Cafe';
    if (cat.contains('bakery')) return 'Bakery';
    if (cat.contains('nightclub') || cat.contains('night club') || cat.contains('disco')) return 'Night Club';
    if (cat.contains('club') || cat.contains('lounge')) return 'Club / Lounge';
    if (cat.contains('bar') || cat.contains('pub')) return 'Bar / Pub';
    if (cat.contains('cocktail') || cat.contains('wine')) return 'Cocktail Bar';
    if (cat.contains('casino') || cat.contains('gambling') || cat.contains('betting')) return 'Casino';
    if (cat.contains('hotel') || cat.contains('lodging')) return 'Hotel';
    if (cat.contains('hostel')) return 'Hostel';
    if (cat.contains('hospital') || cat.contains('medical')) return 'Hospital';
    if (cat.contains('clinic')) return 'Clinic';
    if (cat.contains('pharmacy')) return 'Pharmacy';
    if (cat.contains('university')) return 'University';
    if (cat.contains('school') || cat.contains('college')) return 'School';
    if (cat.contains('library')) return 'Library';
    if (cat.contains('station') || cat.contains('rail')) return 'Station';
    if (cat.contains('airport') || cat.contains('terminal')) return 'Airport';
    if (cat.contains('park') || cat.contains('garden')) return 'Park';
    if (cat.contains('shop') || cat.contains('store') || cat.contains('retail')) return 'Shop';
    if (cat.contains('mall') || cat.contains('shopping')) return 'Shopping Centre';
    if (cat.contains('supermarket') || cat.contains('market')) return 'Supermarket';
    if (cat.contains('museum')) return 'Museum';
    if (cat.contains('gallery') || cat.contains('art')) return 'Art Gallery';
    if (cat.contains('gym') || cat.contains('fitness')) return 'Gym';
    if (cat.contains('stadium') || cat.contains('arena')) return 'Stadium';
    if (cat.contains('cinema')) return 'Cinema';
    if (cat.contains('theater') || cat.contains('theatre')) return 'Theatre';
    if (cat.contains('concert') || cat.contains('entertainment')) return 'Entertainment';
    if (cat.contains('bank') || cat.contains('finance')) return 'Bank';
    if (cat.contains('mosque')) return 'Mosque';
    if (cat.contains('church')) return 'Church';
    if (cat.contains('temple') || cat.contains('synagogue')) return 'Place of Worship';
    if (cat.contains('spa') || cat.contains('beauty')) return 'Spa & Beauty';
    if (cat.contains('salon') || cat.contains('hair')) return 'Salon';
    if (cat.contains('police')) return 'Police';
    if (cat.contains('office') || cat.contains('business')) return 'Office';
    if (cat.contains('postcode') || cat.contains('postal')) return 'Postcode';
    return null;
  }
}
