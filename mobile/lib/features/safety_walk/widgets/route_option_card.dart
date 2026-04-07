import 'package:flutter/material.dart';
import 'package:londonsnaps/features/safety_walk/models/safety_walk_models.dart';

/// TfL-inspired route option card with detailed transport breakdown.
/// Each mode has distinct visual identity: color, icon, info layout.
class RouteOptionCard extends StatelessWidget {
  final RouteOption route;
  final bool isSelected;
  final VoidCallback onTap;

  const RouteOptionCard({
    super.key,
    required this.route,
    required this.isSelected,
    required this.onTap,
  });

  IconData get _modeIcon {
    return switch (route.mode.toLowerCase()) {
      'walking' => Icons.directions_walk_rounded,
      'bus' => Icons.directions_bus_filled_rounded,
      'tube' => Icons.subway_rounded,
      'driving' || 'car' => Icons.directions_car_filled_rounded,
      'mixed' => Icons.transfer_within_a_station_rounded,
      'cycling' => Icons.pedal_bike_rounded,
      _ => Icons.directions_rounded,
    };
  }

  Color get _modeColor {
    return switch (route.mode.toLowerCase()) {
      'walking' => const Color(0xFF00C853),
      'bus' => const Color(0xFFE63946),
      'tube' => const Color(0xFF1565C0),
      'driving' || 'car' => const Color(0xFF7C4DFF),
      'mixed' => const Color(0xFFFF6B35),
      'cycling' => const Color(0xFF26A69A),
      _ => const Color(0xFF9E9E9E),
    };
  }

  String get _modeLabel {
    return switch (route.mode.toLowerCase()) {
      'walking' => 'Walking',
      'bus' => 'Bus',
      'tube' => 'Underground',
      'driving' || 'car' => 'Driving',
      'mixed' => 'Mixed',
      'cycling' => 'Cycling',
      _ => route.mode,
    };
  }

  String get _modeEmoji {
    return switch (route.mode.toLowerCase()) {
      'walking' => '🚶',
      'bus' => '🚌',
      'tube' => '🚇',
      'driving' || 'car' => '🚗',
      'mixed' => '🔄',
      'cycling' => '🚴',
      _ => '🗺️',
    };
  }

  String get _modeDescription {
    return switch (route.mode.toLowerCase()) {
      'walking' => 'Safe pedestrian route',
      'bus' => 'London bus service',
      'tube' => 'TfL Underground',
      'driving' || 'car' => 'Road route',
      'mixed' => 'Multi-modal journey',
      'cycling' => 'Cycle-friendly route',
      _ => 'Route option',
    };
  }

  /// Estimate distance from duration (rough approximation)
  String get _estimatedDistance {
    if (route.distance > 0) {
      return route.formattedDistance;
    }
    final mins = route.duration;
    return switch (route.mode.toLowerCase()) {
      'walking' => '~${(mins * 0.08).toStringAsFixed(1)} km',
      'bus' => '~${(mins * 0.3).toStringAsFixed(1)} km',
      'tube' => '~${(mins * 0.5).toStringAsFixed(1)} km',
      'driving' || 'car' => '~${(mins * 0.5).toStringAsFixed(1)} km',
      'cycling' => '~${(mins * 0.2).toStringAsFixed(1)} km',
      _ => '~${(mins * 0.2).toStringAsFixed(1)} km',
    };
  }

  /// Walking: estimate steps and calories
  String? get _walkingSteps {
    if (route.mode.toLowerCase() != 'walking') return null;
    if (route.calories != null) return null; // Use API data instead
    final steps = (route.duration * 130).toString();
    return '$steps steps';
  }

  String? get _walkingCalories {
    if (route.mode.toLowerCase() != 'walking') return null;
    if (route.calories != null) {
      return '${route.calories} kcal';
    }
    final cal = (route.duration * 4.5).toStringAsFixed(0);
    return '$cal kcal';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _modeColor.withValues(alpha: 0.18),
                    _modeColor.withValues(alpha: 0.06),
                  ],
                )
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2A2A2E), Color(0xFF232326)],
                ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? _modeColor.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.06),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _modeColor.withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: icon + mode label + duration
            Row(
              children: [
                // Mode icon badge
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _modeColor.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _modeIcon,
                    color: isSelected ? _modeColor : Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                // Mode name & description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _modeLabel,
                            style: TextStyle(
                              color: isSelected ? _modeColor : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _modeEmoji,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _modeDescription,
                        style: TextStyle(
                          color: isSelected
                              ? _modeColor.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.3),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Duration badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _modeColor.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    route.formattedDuration,
                    style: TextStyle(
                      color: isSelected ? _modeColor : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Stats row: distance + mode-specific info
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildStatChip(
                  Icons.straighten_rounded,
                  _estimatedDistance,
                ),
                if (_walkingSteps != null) ...[
                  _buildStatChip(
                    Icons.directions_walk_rounded,
                    _walkingSteps!,
                  ),
                  _buildStatChip(
                    Icons.local_fire_department_rounded,
                    _walkingCalories!,
                  ),
                ],
                if (route.fare != null)
                  _buildStatChip(
                    Icons.payments_rounded,
                    route.fare!,
                  ),
                if (route.stopsCount != null && route.stopsCount! > 0)
                  _buildStatChip(
                    Icons.pin_drop_rounded,
                    '${route.stopsCount} stops',
                  ),
                if (route.formattedDepartureTime != null &&
                    route.mode.toLowerCase() != 'walking' &&
                    route.mode.toLowerCase() != 'driving') ...[
                  _buildStatChip(
                    Icons.schedule_rounded,
                    route.formattedDepartureTime!,
                  ),
                  if (route.formattedArrivalTime != null)
                    _buildStatChip(
                      Icons.flag_rounded,
                      route.formattedArrivalTime!,
                    ),
                ],
                if (route.co2 != null && route.co2! > 0)
                  _buildStatChip(
                    Icons.eco_rounded,
                    '${(route.co2! / 1000).toStringAsFixed(1)}kg CO₂',
                  ),
              ],
            ),

            // Legs breakdown (if available)
            if (route.legs.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildLegsBreakdown(),
            ],

            // Selection indicator
            if (isSelected) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: _modeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: _modeColor,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Selected Route',
                      style: TextStyle(
                        color: _modeColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isSelected
                ? _modeColor.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.35),
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: isSelected
                  ? _modeColor.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.45),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegsBreakdown() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.04),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.timeline_rounded,
                color: Colors.white.withValues(alpha: 0.4),
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                'Journey Steps',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Leg chips flow
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: _buildLegChips(),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLegChips() {
    final widgets = <Widget>[];
    for (int i = 0; i < route.legs.length; i++) {
      final leg = route.legs[i];
      final legColor = _getLegColor(leg);
      final legIcon = _getLegIcon(leg);

      // Add arrow separator between legs
      if (i > 0) {
        widgets.add(
          Icon(
            Icons.arrow_forward_rounded,
            color: Colors.white.withValues(alpha: 0.2),
            size: 12,
          ),
        );
      }

      widgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: legColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: legColor.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(legIcon, color: legColor, size: 12),
              const SizedBox(width: 4),
              Text(
                leg.lineName != null && leg.lineName!.isNotEmpty
                    ? leg.lineName!
                    : _getLegModeLabel(leg),
                style: TextStyle(
                  color: legColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(width: 4),
              Text(
                '${leg.duration}m',
                style: TextStyle(
                  color: legColor.withValues(alpha: 0.7),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  Color _getLegColor(RouteLeg leg) {
    // Use TfL line color if available
    if (leg.lineColor != null && leg.lineColor!.isNotEmpty) {
      try {
        final hex = leg.lineColor!.replaceAll('#', '');
        return Color(int.parse('FF$hex', radix: 16));
      } catch (_) {}
    }
    return switch (leg.mode.toLowerCase()) {
      'walking' => const Color(0xFF00C853),
      'bus' => const Color(0xFFE63946),
      'tube' || 'underground' => const Color(0xFF1565C0),
      'dlr' => const Color(0xFF00AFAD),
      'overground' => const Color(0xFFEE7C0E),
      'elizabeth-line' => const Color(0xFF6950A1),
      _ => const Color(0xFF9E9E9E),
    };
  }

  IconData _getLegIcon(RouteLeg leg) {
    return switch (leg.mode.toLowerCase()) {
      'walking' => Icons.directions_walk_rounded,
      'bus' => Icons.directions_bus_filled_rounded,
      'tube' || 'underground' => Icons.subway_rounded,
      'dlr' => Icons.tram_rounded,
      'overground' => Icons.train_rounded,
      'elizabeth-line' => Icons.train_rounded,
      _ => Icons.directions_rounded,
    };
  }

  String _getLegModeLabel(RouteLeg leg) {
    return switch (leg.mode.toLowerCase()) {
      'walking' => 'Walk',
      'bus' => 'Bus',
      'tube' || 'underground' => 'Tube',
      'dlr' => 'DLR',
      'overground' => 'Overground',
      'elizabeth-line' => 'Lizzy Line',
      _ => leg.mode,
    };
  }
}
