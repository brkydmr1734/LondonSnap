import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:londonsnaps/core/services/mapbox_geocoding_service.dart';
import 'package:londonsnaps/features/safety_walk/models/safety_walk_models.dart';
import 'package:londonsnaps/features/safety_walk/providers/safety_walk_provider.dart';
import 'package:londonsnaps/features/safety_walk/presentation/companion_card.dart';
import 'package:londonsnaps/features/safety_walk/widgets/route_option_card.dart';
import 'package:londonsnaps/features/safety_walk/widgets/safety_score_badge.dart';

/// Full-featured bottom sheet for setting up a Safety Walk.
/// Production-ready design with animations, step flow, and rich UI.
class SafetyWalkInviteSheet extends StatefulWidget {
  const SafetyWalkInviteSheet({super.key});

  @override
  State<SafetyWalkInviteSheet> createState() => _SafetyWalkInviteSheetState();
}

class _SafetyWalkInviteSheetState extends State<SafetyWalkInviteSheet>
    with TickerProviderStateMixin {
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _fromController = TextEditingController();
  final FocusNode _destinationFocus = FocusNode();
  final FocusNode _fromFocus = FocusNode();
  final SafetyWalkProvider _provider = SafetyWalkProvider();
  final MapboxGeocodingService _geocoding = MapboxGeocodingService();

  String? _selectedCompanionId;
  bool _isLoadingRoutes = false;
  bool _isLoadingCompanions = false;
  bool _isSendingRequest = false;
  bool _isCancelling = false;
  bool _isSearching = false;
  List<GeocodingResult> _searchResults = [];
  bool _showSearchResults = false;
  bool _isEditingFrom = false;
  bool _isSearchingFrom = false;
  List<GeocodingResult> _fromSearchResults = [];
  bool _showFromSearchResults = false;

  // Current step: 0 = Set Route, 1 = Choose Companion, 2 = Ready
  int _currentStep = 0;

  double _currentLat = 51.5074;
  double _currentLng = -0.1278;
  String _fromName = 'Current Location';
  bool _fromIsGPS = true;
  bool _isLoadingGPS = false;
  double? _destLat;
  double? _destLng;
  String? _destName;
  String _selectedMode = 'mixed';  // Transport mode filter

  // Animations
  late AnimationController _entranceController;
  late AnimationController _pulseController;
  late AnimationController _shimmerController;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  // Quick destinations
  static const _quickDestinations = [
    {'name': 'UCL Campus', 'icon': '🎓', 'lat': 51.5246, 'lng': -0.1340},
    {"name": "King's Cross", 'icon': '🚂', 'lat': 51.5320, 'lng': -0.1240},
    {'name': 'Oxford Circus', 'icon': '🛍️', 'lat': 51.5152, 'lng': -0.1418},
    {'name': 'Camden Town', 'icon': '🎸', 'lat': 51.5392, 'lng': -0.1426},
    {'name': 'Shoreditch', 'icon': '🎨', 'lat': 51.5235, 'lng': -0.0710},
    {'name': 'Waterloo', 'icon': '🌉', 'lat': 51.5031, 'lng': -0.1132},
  ];

  static const _safetyTips = [
    {'icon': '📍', 'tip': 'Share your live location with a trusted friend'},
    {'icon': '🔦', 'tip': 'Stick to well-lit and busy routes at night'},
    {'icon': '🔋', 'tip': 'Keep your phone charged above 20% for safety'},
    {'icon': '👂', 'tip': 'Stay aware — avoid headphones in quiet areas'},
    {'icon': '🆘', 'tip': 'Long-press SOS button for 3s during emergencies'},
  ];

  @override
  void initState() {
    super.initState();
    _provider.loadSafetyScore();
    _provider.addListener(_onProviderUpdate);
    _destinationController.addListener(_onSearchTextChanged);
    _fromController.addListener(_onFromSearchTextChanged);
    _fetchGPSLocation();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _fadeIn = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    ));

    _entranceController.forward();
  }

  @override
  void dispose() {
    _destinationController.removeListener(_onSearchTextChanged);
    _destinationController.dispose();
    _fromController.removeListener(_onFromSearchTextChanged);
    _fromController.dispose();
    _destinationFocus.dispose();
    _fromFocus.dispose();
    _geocoding.dispose();
    _provider.removeListener(_onProviderUpdate);
    _entranceController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _onProviderUpdate() {
    if (mounted) setState(() {});
  }

  /// Fetch real GPS location on init, reverse geocode for display
  Future<void> _fetchGPSLocation() async {
    setState(() => _isLoadingGPS = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLoadingGPS = false);
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          setState(() => _isLoadingGPS = false);
          return;
        }
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _currentLat = pos.latitude;
      _currentLng = pos.longitude;
      _fromIsGPS = true;

      // Reverse geocode for display name
      final result = await _geocoding.reverseGeocode(pos.latitude, pos.longitude);
      if (result != null && mounted) {
        setState(() {
          _fromName = result.name;
          _isLoadingGPS = false;
        });
      } else if (mounted) {
        setState(() {
          _fromName = 'My Location';
          _isLoadingGPS = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fromName = 'Current Location';
          _isLoadingGPS = false;
        });
      }
    }
  }

  /// FROM location search text changed
  void _onFromSearchTextChanged() {
    final query = _fromController.text.trim();
    if (query.length < 2) {
      if (_fromSearchResults.isNotEmpty || _showFromSearchResults) {
        setState(() {
          _fromSearchResults = [];
          _showFromSearchResults = false;
        });
      }
      return;
    }
    setState(() {
      _isSearchingFrom = true;
      _showFromSearchResults = true;
    });
    _geocoding.searchDebounced(
      query,
      proximityLat: _currentLat,
      proximityLng: _currentLng,
      onResults: (results) {
        if (mounted) {
          setState(() {
            _fromSearchResults = results;
            _isSearchingFrom = false;
          });
        }
      },
    );
  }

  /// Select a FROM search result
  void _selectFromResult(GeocodingResult result) {
    HapticFeedback.mediumImpact();
    _fromFocus.unfocus();
    _fromController.removeListener(_onFromSearchTextChanged);
    _fromController.text = result.name;
    _fromController.addListener(_onFromSearchTextChanged);
    setState(() {
      _currentLat = result.latitude;
      _currentLng = result.longitude;
      _fromName = result.name;
      _fromIsGPS = false;
      _isEditingFrom = false;
      _showFromSearchResults = false;
      _fromSearchResults = [];
    });
    // Re-search routes if destination is already set
    if (_destLat != null && _destLng != null) {
      _loadRouteOptions();
    }
  }

  /// Reset FROM to GPS location
  void _resetFromToGPS() {
    HapticFeedback.lightImpact();
    setState(() {
      _isEditingFrom = false;
      _showFromSearchResults = false;
      _fromSearchResults = [];
      _fromController.clear();
    });
    _fetchGPSLocation();
    if (_destLat != null && _destLng != null) {
      _loadRouteOptions();
    }
  }

  /// Cancel an existing walk request
  Future<void> _cancelWalkRequest() async {
    HapticFeedback.mediumImpact();
    setState(() => _isCancelling = true);
    final success = await _provider.cancelWalk();
    setState(() => _isCancelling = false);
    if (success && mounted) {
      HapticFeedback.heavyImpact();
      _showSnackBar('Walk request cancelled', isSuccess: true);
    } else if (_provider.error != null) {
      _showSnackBar(_provider.error!);
    }
  }

  void _onSearchTextChanged() {
    final query = _destinationController.text.trim();
    if (query.length < 2) {
      if (_searchResults.isNotEmpty || _showSearchResults) {
        setState(() {
          _searchResults = [];
          _showSearchResults = false;
        });
      }
      return;
    }

    setState(() {
      _isSearching = true;
      _showSearchResults = true;
    });

    _geocoding.searchDebounced(
      query,
      proximityLat: _currentLat,
      proximityLng: _currentLng,
      onResults: (results) {
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
        }
      },
    );
  }

  void _selectSearchResult(GeocodingResult result) {
    HapticFeedback.mediumImpact();
    _destinationFocus.unfocus();
    _destinationController.removeListener(_onSearchTextChanged);
    _destinationController.text = result.name;
    _destinationController.addListener(_onSearchTextChanged);

    setState(() {
      _destLat = result.latitude;
      _destLng = result.longitude;
      _destName = result.name;
      _showSearchResults = false;
      _searchResults = [];
      _currentStep = 1;
    });

    _loadRouteOptions();
  }

  Future<void> _searchDestination() async {
    final query = _destinationController.text.trim();
    if (query.isEmpty) return;
    _destinationFocus.unfocus();
    HapticFeedback.lightImpact();

    // If we have search results, pick the first one
    if (_searchResults.isNotEmpty) {
      _selectSearchResult(_searchResults.first);
      return;
    }

    // Otherwise do a direct search
    setState(() => _isSearching = true);
    final results = await _geocoding.search(
      query,
      proximityLat: _currentLat,
      proximityLng: _currentLng,
    );
    setState(() => _isSearching = false);

    if (results.isNotEmpty) {
      _selectSearchResult(results.first);
    }
  }

  void _selectQuickDestination(Map<String, dynamic> dest) {
    HapticFeedback.lightImpact();
    _destinationController.text = dest['name'] as String;
    setState(() {
      _destLat = dest['lat'] as double;
      _destLng = dest['lng'] as double;
      _destName = dest['name'] as String;
      _currentStep = 1;
    });
    _loadRouteOptions();
  }

  Future<void> _loadRouteOptions() async {
    if (_destLat == null || _destLng == null) return;
    setState(() => _isLoadingRoutes = true);
    await _provider.getRouteOptions(
        _currentLat, _currentLng, _destLat!, _destLng!,
        mode: _selectedMode);
    setState(() => _isLoadingCompanions = true);
    await _provider.findCompanions(
        _currentLat, _currentLng, _destLat!, _destLng!);
    setState(() {
      _isLoadingRoutes = false;
      _isLoadingCompanions = false;
    });
  }

  Future<void> _sendWalkRequest() async {
    if (_selectedCompanionId == null || _provider.selectedRoute == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _isSendingRequest = true);
    final success = await _provider.requestWalk(_selectedCompanionId!);
    setState(() => _isSendingRequest = false);
    if (success && mounted) {
      HapticFeedback.heavyImpact();
      Navigator.pop(context);
      _showSnackBar('Walk request sent! 🛡️', isSuccess: true);
    } else if (_provider.error != null) {
      _showSnackBar(_provider.error!);
    }
  }

  void _showSnackBar(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        backgroundColor:
            isSuccess ? const Color(0xFF00C853) : const Color(0xFFE63946),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _resetDestination() {
    HapticFeedback.lightImpact();
    setState(() {
      _destLat = null;
      _destLng = null;
      _destName = null;
      _currentStep = 0;
      _selectedCompanionId = null;
      _destinationController.clear();
      _provider.clearRouteOptions();
      _provider.clearCompanions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final hasPendingWalk = _provider.isWalkPending || _provider.isWalkAccepted;

    return FadeTransition(
      opacity: _fadeIn,
      child: SlideTransition(
        position: _slideUp,
        child: Container(
          height: screenHeight * 0.82,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1E1E22), Color(0xFF141416)],
            ),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 30,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildDragHandle(),
              _buildHeader(),
              if (hasPendingWalk) ...
                [Expanded(child: _buildPendingWalkSection())]
              else ...[
                _buildStepIndicator(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLocationCard(),
                        if (_showFromSearchResults) ...[
                          const SizedBox(height: 4),
                          _buildFromSearchResults(),
                        ],
                        if (_showSearchResults) ...[
                          const SizedBox(height: 4),
                          _buildSearchResults(),
                        ],
                        if (_currentStep == 0 &&
                            !_showSearchResults &&
                            !_showFromSearchResults) ...[
                          const SizedBox(height: 20),
                          _buildQuickDestinations(),
                          const SizedBox(height: 24),
                          _buildSafetyTips(),
                        ],
                        if (_destLat != null) ...[
                          const SizedBox(height: 20),
                          _buildRouteOptions(),
                        ],
                        if (_provider.routeOptions.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _buildCompanionSection(),
                        ],
                        SizedBox(height: bottomPad + 80),
                      ],
                    ),
                  ),
                ),
                _buildSendButton(bottomPad),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    final safeScore = _provider.safetyScore?.score ?? 80;
    final totalWalks = _provider.safetyScore?.totalWalks ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          // Animated shield icon
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final glowOpacity = 0.3 + (_pulseController.value * 0.3);
              return Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF6B35), Color(0xFFE63946)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(0xFFFF6B35).withValues(alpha: glowOpacity),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Icon(Icons.shield_rounded,
                    color: Colors.white, size: 26),
              );
            },
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Safety Walk',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  totalWalks > 0
                      ? '$totalWalks walks completed'
                      : 'Walk safely with a companion',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Safety score
          SafetyScoreBadge(score: safeScore, size: 42),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    const steps = ['Set Route', 'Choose Buddy', 'Walk!'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            final stepBefore = index ~/ 2;
            return Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  gradient: stepBefore < _currentStep
                      ? const LinearGradient(
                          colors: [Color(0xFFFF6B35), Color(0xFFE63946)])
                      : null,
                  color: stepBefore < _currentStep
                      ? null
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
            );
          }
          final step = index ~/ 2;
          final isActive = step <= _currentStep;
          final isCurrent = step == _currentStep;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: isCurrent
                  ? const LinearGradient(
                      colors: [Color(0xFFFF6B35), Color(0xFFE63946)])
                  : null,
              color: isCurrent
                  ? null
                  : isActive
                      ? const Color(0xFF00C853).withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: isActive && !isCurrent
                  ? Border.all(
                      color: const Color(0xFF00C853).withValues(alpha: 0.3))
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive && !isCurrent)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.check_circle_rounded,
                        color: Color(0xFF00C853), size: 12),
                  ),
                Text(
                  steps[step],
                  style: TextStyle(
                    color: isCurrent
                        ? Colors.white
                        : isActive
                            ? const Color(0xFF00C853)
                            : Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2A2A2E).withValues(alpha: 0.9),
            const Color(0xFF232326).withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // FROM
          Row(
            children: [
              _locationDot(
                const Color(0xFF00C853),
                Icons.my_location_rounded,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FROM',
                      style: TextStyle(
                        color: const Color(0xFF00C853).withValues(alpha: 0.8),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (_isEditingFrom)
                      TextField(
                        controller: _fromController,
                        focusNode: _fromFocus,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search starting point...',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.25),
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        autofocus: true,
                      )
                    else
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _isEditingFrom = true);
                        },
                        child: Row(
                          children: [
                            if (_isLoadingGPS)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: const Color(0xFF00C853).withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            Flexible(
                              child: Text(
                                _fromName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_fromIsGPS) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00C853).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'GPS',
                                  style: TextStyle(
                                    color: Color(0xFF00C853),
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (_isEditingFrom)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isEditingFrom = false;
                      _showFromSearchResults = false;
                      _fromController.clear();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.close_rounded,
                        color: Colors.white.withValues(alpha: 0.4), size: 16),
                  ),
                )
              else if (!_fromIsGPS)
                GestureDetector(
                  onTap: _resetFromToGPS,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C853).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.gps_fixed_rounded,
                        color: Color(0xFF00C853), size: 16),
                  ),
                )
              else
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _isEditingFrom = true);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.edit_rounded,
                        color: Colors.white.withValues(alpha: 0.4), size: 16),
                  ),
                ),
            ],
          ),

          // Connector
          Padding(
            padding: const EdgeInsets.only(left: 17),
            child: Row(
              children: [
                SizedBox(
                  height: 32,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (i) => Container(
                        width: 2,
                        height: 5,
                        margin: const EdgeInsets.symmetric(vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // TO
          Row(
            children: [
              _locationDot(
                const Color(0xFFE63946),
                Icons.location_on_rounded,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TO',
                      style: TextStyle(
                        color: const Color(0xFFE63946).withValues(alpha: 0.8),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (_destName != null)
                      Text(
                        _destName!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      TextField(
                        controller: _destinationController,
                        focusNode: _destinationFocus,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Where are you heading?',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.25),
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (_) => _searchDestination(),
                      ),
                  ],
                ),
              ),
              if (_destName == null)
                GestureDetector(
                  onTap: _searchDestination,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6B35), Color(0xFFE63946)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFFE63946).withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.search_rounded,
                        color: Colors.white, size: 20),
                  ),
                )
              else
                GestureDetector(
                  onTap: _resetDestination,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.close_rounded,
                        color: Colors.white.withValues(alpha: 0.4), size: 16),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _locationDot(Color color, IconData icon) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }

  Widget _buildFromSearchResults() {
    if (_isSearchingFrom && _fromSearchResults.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF00C853),
            ),
          ),
        ),
      );
    }
    if (_fromSearchResults.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // GPS option at top
            GestureDetector(
              onTap: _resetFromToGPS,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C853).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(Icons.gps_fixed_rounded,
                            color: Color(0xFF00C853), size: 16),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Use Current GPS Location',
                      style: TextStyle(
                        color: Color(0xFF00C853),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ..._fromSearchResults.asMap().entries.map((entry) {
              final index = entry.key;
              final result = entry.value;
              final isLast = index == _fromSearchResults.length - 1;
              return GestureDetector(
                onTap: () => _selectFromResult(result),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : Border(
                            bottom: BorderSide(
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(result.categoryIcon,
                              style: const TextStyle(fontSize: 14)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (result.categoryLabel != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00C853).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      result.categoryLabel!,
                                      style: const TextStyle(
                                        color: Color(0xFF00C853),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                if (result.address != null)
                                  Expanded(
                                    child: Text(
                                      result.address!,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.4),
                                        fontSize: 11,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.north_west_rounded,
                        color: Colors.white.withValues(alpha: 0.2),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingWalkSection() {
    final walk = _provider.activeWalk;
    if (walk == null) return const SizedBox.shrink();

    final isPending = walk.status == SafetyWalkStatus.pending;
    final isAccepted = walk.status == SafetyWalkStatus.accepted;
    final companion = walk.companion ?? walk.requester;
    final statusColor = isPending
        ? const Color(0xFFFFC107)
        : const Color(0xFF00C853);
    final statusText = isPending ? 'Waiting for Response' : 'Accepted!';
    final statusIcon = isPending ? Icons.hourglass_top_rounded : Icons.check_circle_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Animated status indicator
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale = 0.95 + (_pulseController.value * 0.1);
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor.withValues(alpha: 0.1),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.15 * _pulseController.value),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 36),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          // Status text
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isPending
                ? 'Your walk request has been sent.\nWaiting for your companion to respond...'
                : 'Your companion has accepted!\nGet ready to start walking.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          // Companion card
          if (companion != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2E),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [statusColor, statusColor.withValues(alpha: 0.5)],
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.person_rounded, color: Colors.white, size: 26),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          companion.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (companion.universityName != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            companion.universityName!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Transport mode badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getTransportIcon(walk.transportMode),
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          walk.transportMode,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
          // Cancel button
          GestureDetector(
            onTap: _isCancelling ? null : _cancelWalkRequest,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFE63946).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFE63946).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isCancelling)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFE63946),
                      ),
                    )
                  else ...[
                    const Icon(
                      Icons.close_rounded,
                      color: Color(0xFFE63946),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Cancel Walk Request',
                      style: TextStyle(
                        color: Color(0xFFE63946),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isAccepted) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                HapticFeedback.heavyImpact();
                final success = await _provider.startWalk();
                if (success && mounted) {
                  Navigator.pop(context);
                  _showSnackBar('Walk started! Stay safe. 🛡️', isSuccess: true);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00C853), Color(0xFF2E7D32)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00C853).withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Start Walk Now',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  IconData _getTransportIcon(String mode) {
    return switch (mode.toUpperCase()) {
      'WALKING' => Icons.directions_walk_rounded,
      'BUS' => Icons.directions_bus_filled_rounded,
      'TUBE' => Icons.subway_rounded,
      'DRIVING' || 'CAR' => Icons.directions_car_filled_rounded,
      'MIXED' => Icons.transfer_within_a_station_rounded,
      _ => Icons.directions_rounded,
    };
  }

  Widget _buildSearchResults() {
    if (_isSearching && _searchResults.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFFFF6B35),
            ),
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _searchResults.asMap().entries.map((entry) {
            final index = entry.key;
            final result = entry.value;
            final isLast = index == _searchResults.length - 1;

            return GestureDetector(
              onTap: () => _selectSearchResult(result),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : Border(
                          bottom: BorderSide(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                ),
                child: Row(
                  children: [
                    // Category icon
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          result.categoryIcon,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name, category & address
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (result.categoryLabel != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF6B35).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    result.categoryLabel!,
                                    style: const TextStyle(
                                      color: Color(0xFFFF6B35),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              if (result.address != null)
                                Expanded(
                                  child: Text(
                                    result.address!,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.4),
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.north_west_rounded,
                      color: Colors.white.withValues(alpha: 0.2),
                      size: 14,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildQuickDestinations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFFFFC107), size: 18),
            const SizedBox(width: 6),
            Text(
              'Quick Picks',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickDestinations.map((dest) {
            return GestureDetector(
              onTap: () => _selectQuickDestination(dest),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(dest['icon'] as String, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      dest['name'] as String,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSafetyTips() {
    // Pick a random tip to feature
    final tipIndex =
        DateTime.now().minute % _safetyTips.length;
    final tip = _safetyTips[tipIndex];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF00C853).withValues(alpha: 0.08),
            const Color(0xFF00C853).withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.lightbulb_rounded,
                    color: Color(0xFF00C853), size: 16),
              ),
              const SizedBox(width: 10),
              const Text(
                'Safety Tip',
                style: TextStyle(
                  color: Color(0xFF00C853),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(tip['icon']!, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tip['tip']!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.route_rounded,
                color: Color(0xFF64B5F6), size: 18),
            const SizedBox(width: 8),
            const Text(
              'Route Options',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (_provider.routeOptions.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_provider.routeOptions.length} routes',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Transport mode selector
        _buildModeSelector(),
        const SizedBox(height: 14),
        if (_isLoadingRoutes)
          Column(
            children: List.generate(
              3,
              (i) => Padding(
                padding: EdgeInsets.only(bottom: i < 2 ? 10.0 : 0),
                child: _buildLoadingShimmer(height: 100),
              ),
            ),
          )
        else if (_provider.routeOptions.isEmpty)
          _buildEmptyState(
            Icons.alt_route_rounded,
            'No routes available',
            'Try a different transport mode or destination',
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _provider.routeOptions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final route = _provider.routeOptions[index];
              final isSelected = _provider.selectedRoute == route;
              return RouteOptionCard(
                route: route,
                isSelected: isSelected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _provider.selectRoute(route);
                  if (_currentStep < 1) {
                    setState(() => _currentStep = 1);
                  }
                },
              );
            },
          ),
      ],
    );
  }

  static const _transportModes = [
    {'id': 'mixed', 'label': 'All', 'icon': Icons.shuffle_rounded, 'emoji': '🔀'},
    {'id': 'walking', 'label': 'Walk', 'icon': Icons.directions_walk_rounded, 'emoji': '🚶'},
    {'id': 'bus', 'label': 'Bus', 'icon': Icons.directions_bus_filled_rounded, 'emoji': '🚌'},
    {'id': 'tube', 'label': 'Tube', 'icon': Icons.subway_rounded, 'emoji': '🚇'},
    {'id': 'driving', 'label': 'Car', 'icon': Icons.directions_car_filled_rounded, 'emoji': '🚗'},
  ];

  static const _modeColors = {
    'mixed': Color(0xFFFF6B35),
    'walking': Color(0xFF00C853),
    'bus': Color(0xFFE63946),
    'tube': Color(0xFF1565C0),
    'driving': Color(0xFF7C4DFF),
  };

  Widget _buildModeSelector() {
    return SizedBox(
      height: 56,
      child: Row(
        children: _transportModes.map((mode) {
          final id = mode['id'] as String;
          final label = mode['label'] as String;
          final icon = mode['icon'] as IconData;
          final isActive = _selectedMode == id;
          final color = _modeColors[id] ?? const Color(0xFF9E9E9E);

          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_selectedMode == id) return;
                HapticFeedback.selectionClick();
                setState(() => _selectedMode = id);
                // Re-fetch routes with new mode
                if (_destLat != null && _destLng != null) {
                  _provider.clearRouteOptions();
                  _loadRouteOptions();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: isActive
                      ? color.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isActive
                        ? color.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.06),
                    width: isActive ? 1.5 : 1,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.15),
                            blurRadius: 8,
                            spreadRadius: 0,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: isActive
                          ? color
                          : Colors.white.withValues(alpha: 0.4),
                      size: 18,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: TextStyle(
                        color: isActive
                            ? color
                            : Colors.white.withValues(alpha: 0.35),
                        fontSize: 9,
                        fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCompanionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.people_alt_rounded,
                color: Color(0xFFFF6B35), size: 18),
            const SizedBox(width: 8),
            const Text(
              'Available Companions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (_provider.companions.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B35), Color(0xFFE63946)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_provider.companions.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoadingCompanions)
          Column(
            children: List.generate(
              2,
              (i) => Padding(
                padding: EdgeInsets.only(bottom: i < 1 ? 10.0 : 0),
                child: _buildLoadingShimmer(height: 72),
              ),
            ),
          )
        else if (_provider.companions.isEmpty)
          _buildEmptyState(
            Icons.person_search_rounded,
            'No companions nearby',
            'Your friends will appear here when they\'re online',
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _provider.companions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final companion = _provider.companions[index];
              final isSelected = _selectedCompanionId == companion.user.id;
              return CompanionCard(
                companion: companion,
                isSelected: isSelected,
                isInviting: _isSendingRequest && isSelected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedCompanionId = companion.user.id;
                    if (_currentStep < 2) _currentStep = 2;
                  });
                },
                onInvite: () {
                  setState(() {
                    _selectedCompanionId = companion.user.id;
                    _currentStep = 2;
                  });
                  _sendWalkRequest();
                },
              );
            },
          ),
      ],
    );
  }

  Widget _buildSendButton(double bottomPad) {
    final hasValid =
        _selectedCompanionId != null && _provider.selectedRoute != null;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF141416).withValues(alpha: 0.0),
            const Color(0xFF141416),
          ],
        ),
      ),
      child: GestureDetector(
        onTap: hasValid && !_isSendingRequest ? _sendWalkRequest : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: hasValid
                ? const LinearGradient(
                    colors: [Color(0xFFFF6B35), Color(0xFFE63946)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: hasValid ? null : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: hasValid
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.06)),
            boxShadow: hasValid
                ? [
                    BoxShadow(
                      color: const Color(0xFFE63946).withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.shield_rounded,
                color: hasValid
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.2),
                size: 20,
              ),
              const SizedBox(width: 10),
              _isSendingRequest
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(
                      hasValid
                          ? 'Send Walk Request'
                          : _currentStep == 0
                              ? 'Set your destination first'
                              : 'Select a companion',
                      style: TextStyle(
                        color: hasValid
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.2),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingShimmer({required double height}) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _shimmerController.value, 0),
              end: Alignment(1.0 + 2.0 * _shimmerController.value, 0),
              colors: [
                const Color(0xFF2A2A2E),
                const Color(0xFF353538),
                const Color(0xFF2A2A2E),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.15), size: 40),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.25),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
