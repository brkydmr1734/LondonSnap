import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:londonsnaps/features/safety_walk/models/safety_walk_models.dart';
import 'package:londonsnaps/features/safety_walk/widgets/safety_score_badge.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';

/// Colors for the Safety Walk overlay
class _SafetyWalkColors {
  static const card = Color(0xFF2C2C2E);
  static const sosRed = Color(0xFFE63946);
  static const safetyGreen = Color(0xFF00C853);
  static const warningYellow = Color(0xFFFFD600);
  static const distanceOrange = Color(0xFFFF6B35);
  static const textSecondary = Color(0xFF8E8E93);
}

/// Active Walk Overlay that renders on top of the map during a Safety Walk.
class ActiveWalkOverlay extends StatefulWidget {
  final SafetyWalk walk;
  final SafetyWalkLocation? userLocation;
  final SafetyWalkLocation? companionLocation;
  final List<Map<String, double>> routePoints;
  final VoidCallback onEndWalk;
  final VoidCallback onOpenChat;
  final VoidCallback onSOS;

  const ActiveWalkOverlay({
    super.key,
    required this.walk,
    this.userLocation,
    this.companionLocation,
    required this.routePoints,
    required this.onEndWalk,
    required this.onOpenChat,
    required this.onSOS,
  });

  @override
  State<ActiveWalkOverlay> createState() => _ActiveWalkOverlayState();

  /// Build route polyline for FlutterMap
  static Polyline buildRoutePolyline(List<Map<String, double>> routePoints) {
    final points = routePoints
        .map((p) => LatLng(p['lat'] ?? 0, p['lng'] ?? 0))
        .toList();
    return Polyline(
      points: points,
      color: const Color(0xFF6366F1),
      strokeWidth: 4,
    );
  }

  /// Build companion marker for FlutterMap
  static Marker buildCompanionMarker(
    SafetyWalkLocation location,
    SafetyWalkUser? companion,
  ) {
    return Marker(
      point: LatLng(location.latitude, location.longitude),
      width: 50,
      height: 50,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _SafetyWalkColors.safetyGreen,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: _SafetyWalkColors.safetyGreen.withValues(alpha: 0.4),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: AvatarWidget(
          avatarUrl: companion?.avatarUrl,
          radius: 22,
        ),
      ),
    );
  }
}

class _ActiveWalkOverlayState extends State<ActiveWalkOverlay>
    with SingleTickerProviderStateMixin {
  Timer? _etaTimer;
  int _remainingSeconds = 0;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _calculateRemainingTime();
    _startEtaTimer();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _etaTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _calculateRemainingTime() {
    if (widget.walk.startedAt != null && widget.walk.estimatedDuration != null) {
      final elapsed = DateTime.now().difference(widget.walk.startedAt!).inSeconds;
      final totalSeconds = widget.walk.estimatedDuration! * 60;
      _remainingSeconds = math.max(0, totalSeconds - elapsed);
    }
  }

  void _startEtaTimer() {
    _etaTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        }
      });
    });
  }

  String get _formattedEta {
    if (_remainingSeconds <= 0) return 'Arrived';
    final mins = _remainingSeconds ~/ 60;
    final secs = _remainingSeconds % 60;
    if (mins == 0) return '${secs}s remaining';
    return '$mins min remaining';
  }

  /// Calculate distance between user and companion using Haversine formula
  double? get _companionDistance {
    if (widget.userLocation == null || widget.companionLocation == null) {
      return null;
    }
    return _haversineDistance(
      widget.userLocation!.latitude,
      widget.userLocation!.longitude,
      widget.companionLocation!.latitude,
      widget.companionLocation!.longitude,
    );
  }

  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000; // Earth's radius in meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double deg) => deg * math.pi / 180;

  Color _getDistanceColor(double meters) {
    if (meters < 100) return _SafetyWalkColors.safetyGreen;
    if (meters < 200) return _SafetyWalkColors.warningYellow;
    if (meters < 500) return _SafetyWalkColors.distanceOrange;
    return _SafetyWalkColors.sosRed;
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  void _showCancelConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _SafetyWalkColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Cancel Walk?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to cancel this Safety Walk? Your companion will be notified.',
          style: TextStyle(color: _SafetyWalkColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No, Keep Walking'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onEndWalk();
            },
            style: TextButton.styleFrom(foregroundColor: _SafetyWalkColors.sosRed),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  void _showEndWalkConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _SafetyWalkColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'End Walk?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Have you reached your destination safely?',
          style: TextStyle(color: _SafetyWalkColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not Yet'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onEndWalk();
            },
            style: TextButton.styleFrom(
              foregroundColor: _SafetyWalkColors.safetyGreen,
            ),
            child: const Text('Yes, End Walk'),
          ),
        ],
      ),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _SafetyWalkColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.report_outlined, color: Colors.orange),
              title: const Text('Report Companion', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                // TODO: Implement report functionality
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined, color: Colors.white),
              title: const Text('Mute Notifications', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                // TODO: Implement mute functionality
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final companion = widget.walk.companion ?? widget.walk.requester;
    final distance = _companionDistance;

    return Stack(
      children: [
        // Top Bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildTopBar(),
        ),

        // Distance Pill (centered)
        if (distance != null)
          Positioned.fill(
            child: Center(
              child: _buildDistancePill(distance),
            ),
          ),

        // Bottom Section: Companion Info + End Walk + SOS
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildBottomSection(companion),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.8),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Back button
                  GestureDetector(
                    onTap: _showCancelConfirmation,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title with pulsing dot
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) => Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _SafetyWalkColors.safetyGreen
                                  .withValues(alpha: _pulseAnimation.value),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _SafetyWalkColors.safetyGreen
                                      .withValues(alpha: 0.5 * _pulseAnimation.value),
                                  blurRadius: 6,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Safety Walk Active',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // More options
                  GestureDetector(
                    onTap: _showMoreOptions,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.more_horiz,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // ETA
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'ETA: $_formattedEta',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDistancePill(double distance) {
    final color = _getDistanceColor(distance);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_pin_circle, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            _formatDistance(distance),
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSection(SafetyWalkUser? companion) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Companion Info Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _SafetyWalkColors.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    // Avatar
                    AvatarWidget(
                      avatarUrl: companion?.avatarUrl,
                      radius: 22,
                      showBorder: true,
                      borderColor: _SafetyWalkColors.safetyGreen,
                    ),
                    const SizedBox(width: 12),
                    // Name and university
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            companion?.displayName ?? 'Companion',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (companion?.universityName != null)
                            Text(
                              companion!.universityName!,
                              style: const TextStyle(
                                color: _SafetyWalkColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Safety Score
                    if (widget.walk.safetyScore != null) ...[
                      SafetyScoreBadge(
                        score: widget.walk.safetyScore!,
                        size: 32,
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Chat Button
                    GestureDetector(
                      onTap: widget.onOpenChat,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.chat_bubble_outline,
                          color: Color(0xFF6366F1),
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // End Walk Button + SOS
              Row(
                children: [
                  // End Walk Button
                  Expanded(
                    child: GestureDetector(
                      onTap: _showEndWalkConfirmation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _SafetyWalkColors.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'End Walk',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // SOS Button placeholder - actual SOS button will be overlaid
                  GestureDetector(
                    onTap: widget.onSOS,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _SafetyWalkColors.sosRed,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _SafetyWalkColors.sosRed.withValues(alpha: 0.5),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'SOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
