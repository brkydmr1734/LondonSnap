import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/auth/providers/auth_provider.dart';
import 'package:londonsnaps/features/map/models/map_models.dart';
import 'package:londonsnaps/features/map/models/poi_models.dart';
import 'package:londonsnaps/features/map/painters/gta5_pin_painter.dart';
import 'package:londonsnaps/features/map/providers/snap_map_provider.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';
import 'package:londonsnaps/core/config/app_config.dart';
import 'package:londonsnaps/features/safety_walk/providers/safety_walk_provider.dart';
import 'package:londonsnaps/features/safety_walk/presentation/safety_walk_invite_sheet.dart';

const _kMapboxToken = AppConfig.mapboxAccessToken;

class SnapMapScreen extends ConsumerStatefulWidget {
  const SnapMapScreen({super.key});

  @override
  ConsumerState<SnapMapScreen> createState() => _SnapMapScreenState();
}

class _SnapMapScreenState extends ConsumerState<SnapMapScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  bool _mapReady = false;
  double _currentZoom = 13.5; // Track zoom for slider sync

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final loc = ref.read(snapMapProvider).userLocation;
      if (loc != null && _mapReady) {
        _mapController.move(loc, 14.0);
      }
    });
  }

  void _animateTo(LatLng target) {
    if (!_mapReady) return;
    _mapController.move(target, 15.0);
  }

  void _showPoiDetail(BuildContext context, PoiPin poi) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Consumer(
        builder: (ctx, ref, _) => _PoiDetailSheet(
          poi: poi,
          onDirections: () {
            Navigator.pop(ctx);
            ref.read(snapMapProvider.notifier).fetchDirections(
              poi.position,
              poi.name,
            );
            // Animate to show the route
            if (_mapReady) {
              _mapController.move(poi.position, 14.5);
            }
          },
        ),
      ),
    );
  }

  void _openSafetyWalkSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const SafetyWalkInviteSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(snapMapProvider);
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    ref.listen(snapMapProvider, (prev, next) {
      if (prev?.userLocation == null &&
          next.userLocation != null &&
          _mapReady) {
        _mapController.move(next.userLocation!, 14.0);
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Full-screen Map layer ──
          Container(
            color: const Color(0xFF1A1A2E), // Dark background matching map theme
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: mapState.userLocation ?? const LatLng(51.5074, -0.1278),
                initialZoom: 13.5,
                minZoom: 9.0,
                maxZoom: 17.0, // Strict limit to prevent white screen (dark-v11 tiles safe at 17)
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
                onMapReady: () => setState(() => _mapReady = true),
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture) {
                    setState(() => _currentZoom = position.zoom);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://api.mapbox.com/styles/v1/mapbox/dark-v11/tiles/256/{z}/{x}/{y}@2x?access_token=$_kMapboxToken',
                  userAgentPackageName: 'com.londonsnaps.app',
                  maxZoom: 19,
                  retinaMode: true,
                  evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
                ),
                // Event markers (behind users)
                if (mapState.filter != MapFilter.friends)
                  MarkerLayer(
                    markers: mapState.nearbyEvents
                        .map((e) => Marker(
                              point: e.position,
                              width: 90,
                              height: 52,
                              child: _EventMarker(event: e),
                            ))
                        .toList(),
                  ),
                // User markers
                if (mapState.filter != MapFilter.events)
                  MarkerLayer(
                    markers: mapState.nearbyUsers
                        .map((u) => Marker(
                              point: u.position,
                              width: 80,
                              height: 68,
                              child: _UserMarker(user: u),
                            ))
                        .toList(),
                  ),
                // POI markers (GTA5-style pins)
                if (mapState.visiblePois.isNotEmpty)
                  MarkerLayer(
                    markers: mapState.visiblePois
                        .map((poi) => Marker(
                              point: poi.position,
                              width: 52,
                              height: 64,
                              child: GestureDetector(
                                onTap: () => _showPoiDetail(context, poi),
                                child: CustomPaint(
                                  size: const Size(52, 64),
                                  painter: Gta5PinPainter(
                                    color: poi.category.color,
                                    icon: poi.category.icon,
                                  ),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                // Route polyline overlay
                if (mapState.activeRoute != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: mapState.activeRoute!.polylinePoints,
                        color: const Color(0xFF4A90FF),
                        strokeWidth: 5.0,
                        borderColor: const Color(0xFF1A5CCC),
                        borderStrokeWidth: 1.5,
                      ),
                    ],
                  ),
                // Route destination marker
                if (mapState.activeRoute != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: mapState.activeRoute!.destination,
                        width: 36,
                        height: 36,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A90FF),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x664A90FF),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.flag_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                // Current user marker (always on top)
                if (mapState.userLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: mapState.userLocation!,
                        width: 64,
                        height: 64,
                        child: _CurrentUserMarker(ghostMode: mapState.ghostMode),
                      ),
                    ],
                  ),
                // Mapbox attribution
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('Mapbox', onTap: null),
                    TextSourceAttribution('OpenStreetMap contributors', onTap: null),
                  ],
                  alignment: AttributionAlignment.bottomRight,
                ),
              ],
            ),
          ),

          // ── Top overlay (Snapchat-style) ──
          Positioned(
            top: safeTop + 8,
            left: 16,
            right: 16,
            child: _SnapchatTopOverlay(
              nearbyUsers: mapState.nearbyUsers,
              onFriendTap: (u) => _animateTo(u.position),
              ghostMode: mapState.ghostMode,
            ),
          ),

          // ── Filter chips row ──
          Positioned(
            top: safeTop + 68,
            left: 0,
            right: 0,
            child: _SnapchatFilterChips(
              filter: mapState.filter,
              onFilterChanged: (f) => ref.read(snapMapProvider.notifier).setFilter(f),
            ),
          ),

          // ── Snapchat-style vertical zoom slider (right edge) ──
          Positioned(
            right: 16,
            top: MediaQuery.of(context).size.height * 0.22,
            bottom: MediaQuery.of(context).size.height * 0.42,
            child: _SnapchatZoomSlider(
              minZoom: 9.0,
              maxZoom: 17.0,
              currentZoom: _currentZoom,
              onZoomChanged: (zoom) {
                setState(() => _currentZoom = zoom);
                _mapController.move(
                  _mapController.camera.center,
                  zoom,
                );
              },
            ),
          ),

          // ── Right side buttons (Snapchat-style vertical stack) ──
          Positioned(
            right: 12,
            bottom: safeBottom + 90,
            child: _SnapchatRightButtons(
              isLocating: mapState.isLocating,
              showPois: mapState.showPois,
              ghostMode: mapState.ghostMode,
              activePoiFilters: mapState.activePoiFilters,
              onLocateTap: () async {
                await ref.read(snapMapProvider.notifier).relocate();
                final loc = ref.read(snapMapProvider).userLocation;
                if (loc != null) _animateTo(loc);
              },
              onToggleCategory: (cat) =>
                  ref.read(snapMapProvider.notifier).togglePoiCategory(cat),
              onClearAll: () =>
                  ref.read(snapMapProvider.notifier).clearPoiFilters(),
              onToggleShow: () =>
                  ref.read(snapMapProvider.notifier).toggleShowPois(),
              onGhostToggle: () =>
                  ref.read(snapMapProvider.notifier).toggleGhostMode(),
              onSafetyWalkTap: () => _openSafetyWalkSheet(context),
            ),
          ),

          // ── Route info overlay ──
          if (mapState.activeRoute != null)
            Positioned(
              bottom: safeBottom + 90,
              left: 16,
              right: 72,
              child: _RouteInfoPanel(
                route: mapState.activeRoute!,
                isLoading: mapState.isLoadingRoute,
                onClose: () => ref.read(snapMapProvider.notifier).clearRoute(),
              ),
            ),
          if (mapState.isLoadingRoute)
            Positioned(
              bottom: safeBottom + 100,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF4A90FF).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF4A90FF),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Finding route...',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

          // ── Bottom friend avatars row (Snapchat-style) ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _SnapchatFriendAvatarsRow(
              friends: mapState.nearbyUsers,
              onFriendTap: (u) => _animateTo(u.position),
              safeBottom: safeBottom,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// SNAPCHAT-STYLE TOP OVERLAY (Avatar + Area Name + Weather + Friend)
// ──────────────────────────────────────────────────────────────────

class _SnapchatTopOverlay extends StatelessWidget {
  final List<MapUserPin> nearbyUsers;
  final ValueChanged<MapUserPin> onFriendTap;
  final bool ghostMode;

  const _SnapchatTopOverlay({
    required this.nearbyUsers,
    required this.onFriendTap,
    this.ghostMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final authProvider = AuthProvider();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Current user avatar - tappable, navigates to profile
        GestureDetector(
          onTap: () => context.go('/profile'),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFFFFC00), Color(0xFFFFD700)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFFC00).withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            padding: const EdgeInsets.all(2),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black,
              ),
              padding: const EdgeInsets.all(1.5),
              child: authProvider.currentUser?.avatarUrl != null && authProvider.currentUser!.avatarUrl!.isNotEmpty
                  ? AvatarWidget(
                      avatarUrl: authProvider.currentUser!.avatarUrl,
                      radius: 18,
                    )
                  : CircleAvatar(
                      radius: 18,
                      backgroundColor: AppTheme.primaryColor,
                      child: Text(
                        (authProvider.currentUser?.displayName ?? '?')
                            .split(' ')
                            .map((w) => w.isNotEmpty ? w[0] : '')
                            .take(2)
                            .join()
                            .toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        
        // Center: Area name + Weather
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Canary Wharf',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_outlined,
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '11 °C',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Right: Friend add button + Friend avatar
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Friend add button
            GestureDetector(
              onTap: () => context.push('/friends'),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.5),
                  border: Border.all(color: Colors.white24, width: 1.5),
                ),
                child: const Icon(
                  Icons.person_add_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Friend avatar or search
            if (nearbyUsers.isNotEmpty)
              GestureDetector(
                onTap: () => onFriendTap(nearbyUsers.first),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ghostMode ? Colors.white38 : const Color(0xFF00BFFF),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: ghostMode
                            ? Colors.transparent
                            : Colors.black.withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _buildFriendAvatar(nearbyUsers.first),
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: () => context.push('/friends'),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.5),
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  child: const Icon(
                    Icons.search,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildFriendAvatar(MapUserPin user) {
    if (user.avatarUrl != null && user.avatarUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: user.avatarUrl!,
        fit: BoxFit.cover,
        placeholder: (_, _) => _avatarPlaceholder(user.displayName),
        errorWidget: (_, _, _) => _avatarPlaceholder(user.displayName),
      );
    }
    return _avatarPlaceholder(user.displayName);
  }

  Widget _avatarPlaceholder(String name) {
    return Container(
      color: AppTheme.surfaceColor,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// SNAPCHAT-STYLE FILTER CHIPS
// ──────────────────────────────────────────────────────────────────

class _SnapchatFilterChips extends StatelessWidget {
  final MapFilter filter;
  final ValueChanged<MapFilter> onFilterChanged;

  const _SnapchatFilterChips({
    required this.filter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _SnapFilterChip(
            icon: Icons.photo_camera_outlined,
            label: 'Memories',
            isSelected: false,
            onTap: () {},
          ),
          const SizedBox(width: 8),
          _SnapFilterChip(
            icon: Icons.trending_up_rounded,
            label: 'Trending',
            isSelected: false,
            onTap: () {},
          ),
          const SizedBox(width: 8),
          _SnapFilterChip(
            icon: Icons.directions_walk_rounded,
            label: 'Footprints',
            isSelected: false,
            onTap: () {},
          ),
          const SizedBox(width: 8),
          _SnapFilterChip(
            icon: Icons.access_time_rounded,
            label: 'Visited',
            isSelected: false,
            onTap: () {},
          ),
          const SizedBox(width: 8),
          // Map filter chips (existing functionality)
          ...MapFilter.values.map((f) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _SnapFilterChip(
              icon: _getFilterIcon(f),
              label: f.label,
              isSelected: filter == f,
              onTap: () => onFilterChanged(f),
            ),
          )),
        ],
      ),
    );
  }

  IconData _getFilterIcon(MapFilter f) {
    switch (f) {
      case MapFilter.all:
        return Icons.public_rounded;
      case MapFilter.friends:
        return Icons.people_rounded;
      case MapFilter.events:
        return Icons.event_rounded;
    }
  }
}

class _SnapFilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SnapFilterChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.white38 : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on MapFilter {
  String get label {
    switch (this) {
      case MapFilter.all:
        return 'All';
      case MapFilter.friends:
        return 'Friends';
      case MapFilter.events:
        return 'Events';
    }
  }
}

// ──────────────────────────────────────────────────────────────────
// SNAPCHAT-STYLE RIGHT SIDE BUTTONS
// ──────────────────────────────────────────────────────────────────

class _SnapchatRightButtons extends StatefulWidget {
  final bool isLocating;
  final bool showPois;
  final bool ghostMode;
  final Set<PoiCategory> activePoiFilters;
  final VoidCallback onLocateTap;
  final ValueChanged<PoiCategory> onToggleCategory;
  final VoidCallback onClearAll;
  final VoidCallback onToggleShow;
  final VoidCallback onGhostToggle;
  final VoidCallback onSafetyWalkTap;

  const _SnapchatRightButtons({
    required this.isLocating,
    required this.showPois,
    required this.ghostMode,
    required this.activePoiFilters,
    required this.onLocateTap,
    required this.onToggleCategory,
    required this.onClearAll,
    required this.onToggleShow,
    required this.onGhostToggle,
    required this.onSafetyWalkTap,
  });

  @override
  State<_SnapchatRightButtons> createState() => _SnapchatRightButtonsState();
}

class _SnapchatRightButtonsState extends State<_SnapchatRightButtons> {
  bool _showPoiPanel = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Filter/Tune button (POI filter)
        _SnapchatIconButton(
          icon: _showPoiPanel ? Icons.close_rounded : Icons.tune_rounded,
          isActive: _showPoiPanel,
          onTap: () => setState(() => _showPoiPanel = !_showPoiPanel),
        ),
        
        // POI Filter Panel (expandable)
        if (_showPoiPanel) ...[
          const SizedBox(height: 8),
          _buildPoiPanel(),
        ],
        
        const SizedBox(height: 10),
        
        // Location button
        _SnapchatIconButton(
          icon: Icons.my_location_rounded,
          iconColor: AppTheme.primaryColor,
          isLoading: widget.isLocating,
          onTap: widget.onLocateTap,
        ),
        const SizedBox(height: 10),

        // Safety Walk FAB
        _SafetyWalkFAB(onTap: widget.onSafetyWalkTap),
        const SizedBox(height: 10),

        // Ghost mode button
        _SnapchatIconButton(
          icon: widget.ghostMode ? Icons.visibility_off : Icons.visibility,
          iconColor: widget.ghostMode ? Colors.orange : Colors.white,
          isActive: widget.ghostMode,
          onTap: widget.onGhostToggle,
        ),
        const SizedBox(height: 10),
        
        // User initial badge
        _SnapchatInitialBadge(initial: 'K'),
      ],
    );
  }

  Widget _buildPoiPanel() {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                const Text(
                  'Places',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onToggleShow,
                  child: Icon(
                    widget.showPois ? Icons.visibility : Icons.visibility_off,
                    color: widget.showPois ? AppTheme.primaryColor : Colors.white38,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          // Category items (scrollable)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: PoiCategory.values.map((cat) {
                  final active = widget.activePoiFilters.isEmpty ||
                      widget.activePoiFilters.contains(cat);
                  return GestureDetector(
                    onTap: () => widget.onToggleCategory(cat),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: active
                                  ? cat.color.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              cat.icon,
                              color: active ? cat.color : Colors.white24,
                              size: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cat.label,
                              style: TextStyle(
                                color: active ? Colors.white : Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (widget.activePoiFilters.contains(cat))
                            Icon(Icons.check, color: cat.color, size: 14),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          if (widget.activePoiFilters.isNotEmpty) ...[
            const Divider(height: 1, color: Colors.white12),
            GestureDetector(
              onTap: widget.onClearAll,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Show All',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SnapchatIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;
  final bool isActive;
  final bool isLoading;

  const _SnapchatIconButton({
    required this.icon,
    required this.onTap,
    this.iconColor,
    this.isActive = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.primaryColor.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.65),
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive ? AppTheme.primaryColor : Colors.white12,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
            ),
          ],
        ),
        child: isLoading
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(iconColor ?? Colors.white),
                ),
              )
            : Icon(icon, color: iconColor ?? Colors.white, size: 22),
      ),
    );
  }
}

class _SnapchatInitialBadge extends StatelessWidget {
  final String initial;

  const _SnapchatInitialBadge({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 8,
          ),
        ],
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// SAFETY WALK FAB (with pulse animation when active)
// ──────────────────────────────────────────────────────────────────

class _SafetyWalkFAB extends StatefulWidget {
  final VoidCallback onTap;

  const _SafetyWalkFAB({required this.onTap});

  @override
  State<_SafetyWalkFAB> createState() => _SafetyWalkFABState();
}

class _SafetyWalkFABState extends State<_SafetyWalkFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final SafetyWalkProvider _provider = SafetyWalkProvider();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _provider.addListener(_onProviderUpdate);
    _updatePulse();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _provider.removeListener(_onProviderUpdate);
    super.dispose();
  }

  void _onProviderUpdate() {
    _updatePulse();
    if (mounted) setState(() {});
  }

  void _updatePulse() {
    if (_provider.hasActiveWalk) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveWalk = _provider.hasActiveWalk;
    final gradientColors = hasActiveWalk
        ? [const Color(0xFF00C853), const Color(0xFF2E7D32)]
        : [const Color(0xFFFF6B35), const Color(0xFFE63946)];
    final glowColor = hasActiveWalk
        ? const Color(0xFF00C853)
        : const Color(0xFFE63946);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (_, _) => Transform.scale(
          scale: hasActiveWalk ? _pulseAnimation.value : 1.0,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// SNAPCHAT-STYLE VERTICAL ZOOM SLIDER
// ──────────────────────────────────────────────────────────────────

class _SnapchatZoomSlider extends StatelessWidget {
  final double minZoom;
  final double maxZoom;
  final double currentZoom;
  final ValueChanged<double> onZoomChanged;

  const _SnapchatZoomSlider({
    required this.minZoom,
    required this.maxZoom,
    required this.currentZoom,
    required this.onZoomChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Plus icon at top
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              '+',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Vertical slider
          Expanded(
            child: RotatedBox(
              quarterTurns: 3, // Make slider vertical (bottom = min, top = max)
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  activeTrackColor: Colors.white.withValues(alpha: 0.8),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                  thumbColor: Colors.white,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                  overlayColor: Colors.white.withValues(alpha: 0.1),
                ),
                child: Slider(
                  value: currentZoom.clamp(minZoom, maxZoom),
                  min: minZoom,
                  max: maxZoom,
                  onChanged: onZoomChanged,
                ),
              ),
            ),
          ),
          // Minus icon at bottom
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '−',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// SNAPCHAT-STYLE BOTTOM FRIEND AVATARS ROW
// ──────────────────────────────────────────────────────────────────

class _SnapchatFriendAvatarsRow extends StatelessWidget {
  final List<MapUserPin> friends;
  final ValueChanged<MapUserPin> onFriendTap;
  final double safeBottom;

  const _SnapchatFriendAvatarsRow({
    required this.friends,
    required this.onFriendTap,
    required this.safeBottom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70 + safeBottom,
      padding: EdgeInsets.only(bottom: safeBottom),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.black.withValues(alpha: 0.3),
            Colors.transparent,
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          // Friend avatars
          ...friends.map((friend) => Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _SnapFriendAvatar(
              user: friend,
              onTap: () => onFriendTap(friend),
            ),
          )),
        ],
      ),
    );
  }
}

class _SnapFriendAvatar extends StatelessWidget {
  final MapUserPin user;
  final VoidCallback onTap;

  const _SnapFriendAvatar({
    required this.user,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: user.isOnline
                    ? const Color(0xFFFF6B35) // Snapchat orange for online
                    : Colors.white24,
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 6,
                ),
              ],
            ),
            child: ClipOval(
              child: _buildAvatarContent(),
            ),
          ),
          // Home indicator badge (like Snapchat's home icon on some avatars)
          if (user.isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: const Icon(
                  Icons.home_rounded,
                  color: Colors.white,
                  size: 9,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvatarContent() {
    if (user.avatarUrl != null && user.avatarUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: user.avatarUrl!,
        fit: BoxFit.cover,
        placeholder: (_, _) => _avatarPlaceholder(user.displayName),
        errorWidget: (_, _, _) => _avatarPlaceholder(user.displayName),
      );
    }
    return _avatarPlaceholder(user.displayName);
  }

  Widget _avatarPlaceholder(String name) {
    return Container(
      color: AppTheme.surfaceColor,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// CURRENT USER MARKER (pulsing)
// ──────────────────────────────────────────────────────────────────

class _CurrentUserMarker extends StatefulWidget {
  final bool ghostMode;
  const _CurrentUserMarker({this.ghostMode = false});

  @override
  State<_CurrentUserMarker> createState() => _CurrentUserMarkerState();
}

class _CurrentUserMarkerState extends State<_CurrentUserMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _ctrl.repeat(); // Always animate – pulsing ring or ghost bob
    _scale = Tween<double>(begin: 1.0, end: 2.8)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _opacity = Tween<double>(begin: 0.55, end: 0.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ghost = widget.ghostMode;
    if (ghost) return _buildGhostPin();
    return _buildNormalPin();
  }

  Widget _buildNormalPin() {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) => Transform.scale(
              scale: _scale.value,
              child: Opacity(
                opacity: _opacity.value,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.6),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildGhostPin() {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final t = _ctrl.value;
        final bob = math.sin(t * 2 * math.pi) * 3.0;
        final gOp = 0.55 + 0.25 * math.sin(t * 2 * math.pi);
        return SizedBox(
          width: 64,
          height: 72,
          child: Transform.translate(
            offset: Offset(0, bob),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: gOp,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.25),
                          Colors.blueGrey.withValues(alpha: 0.12),
                        ],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.08),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        '\u{1F47B}',
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'GHOST',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 7,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// USER MARKER
// ──────────────────────────────────────────────────────────────────

class _UserMarker extends StatelessWidget {
  final MapUserPin user;

  const _UserMarker({required this.user});

  @override
  Widget build(BuildContext context) {
    // All users now use circular marker (no more full-body 3D avatar)
    return _buildCircularMarker();
  }

  /// Builds circular marker for users with photo or placeholder
  Widget _buildCircularMarker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: user.isOnline
                      ? AppTheme.successColor
                      : Colors.white38,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipOval(
                child: _buildCircularAvatarContent(),
              ),
            ),
            if (user.isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: AppTheme.successColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            user.displayName.split(' ').first,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// Builds avatar content with priority: avatarUrl > placeholder
  Widget _buildCircularAvatarContent() {
    // Priority 2: Profile photo URL
    if (user.avatarUrl != null && user.avatarUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: user.avatarUrl!,
        fit: BoxFit.cover,
        placeholder: (_, _) => _avatarPlaceholder(user.displayName),
        errorWidget: (_, _, _) => _avatarPlaceholder(user.displayName),
      );
    }
    
    // Priority 3: Text placeholder
    return _avatarPlaceholder(user.displayName);
  }

  Widget _avatarPlaceholder(String name) {
    return Container(
      color: AppTheme.surfaceColor,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// EVENT MARKER
// ──────────────────────────────────────────────────────────────────

class _EventMarker extends StatelessWidget {
  final MapEventPin event;

  const _EventMarker({required this.event});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: event.categoryColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: event.categoryColor.withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(event.category.icon, color: Colors.white, size: 13),
              const SizedBox(width: 4),
              Text(
                event.attendeeCount > 0
                    ? '${event.attendeeCount}'
                    : event.formattedTime,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        CustomPaint(
          size: const Size(12, 6),
          painter: _TrianglePainter(color: event.categoryColor),
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}



// ──────────────────────────────────────────────────────────────────
// POI DETAIL BOTTOM SHEET
// ──────────────────────────────────────────────────────────────────

class _PoiDetailSheet extends StatelessWidget {
  final PoiPin poi;
  final VoidCallback onDirections;
  const _PoiDetailSheet({required this.poi, required this.onDirections});

  @override
  Widget build(BuildContext context) {
    final cat = poi.category;
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cat.color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: cat.color.withValues(alpha: 0.15),
            blurRadius: 24,
            spreadRadius: 4,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle + category banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cat.color.withValues(alpha: 0.2),
                  cat.color.withValues(alpha: 0.05),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cat.color.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                // Category chip
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: cat.color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: cat.color.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(cat.icon, color: cat.color, size: 14),
                          const SizedBox(width: 5),
                          Text(
                            cat.label,
                            style: TextStyle(
                              color: cat.color,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Rating
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFFBBF24), size: 18),
                        const SizedBox(width: 3),
                        Text(
                          poi.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Venue info
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                Text(
                  poi.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                // Address + price row
                Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        color: AppTheme.textMuted, size: 15),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        poi.address,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (poi.priceLevel != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          poi.priceLevel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                // Description
                if (poi.description != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    poi.description!,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // Status + actions
                Row(
                  children: [
                    // Open/closed indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: poi.isOpen
                            ? AppTheme.successColor.withValues(alpha: 0.15)
                            : AppTheme.errorColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: poi.isOpen
                              ? AppTheme.successColor.withValues(alpha: 0.4)
                              : AppTheme.errorColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: poi.isOpen
                                  ? AppTheme.successColor
                                  : AppTheme.errorColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            poi.isOpen ? 'Open Now' : 'Closed',
                            style: TextStyle(
                              color: poi.isOpen
                                  ? AppTheme.successColor
                                  : AppTheme.errorColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Directions button
                    GestureDetector(
                      onTap: onDirections,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [cat.color, cat.color.withValues(alpha: 0.7)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: cat.color.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.near_me_rounded,
                                color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Directions',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// ROUTE INFO PANEL
// ──────────────────────────────────────────────────────────────────

class _RouteInfoPanel extends StatelessWidget {
  final MapRouteInfo route;
  final bool isLoading;
  final VoidCallback onClose;

  const _RouteInfoPanel({
    required this.route,
    required this.isLoading,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4A90FF).withValues(alpha: 0.3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x664A90FF),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with close
          Row(
            children: [
              const Icon(Icons.directions_walk_rounded, color: Color(0xFF4A90FF), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  route.destinationName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: onClose,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Distance and duration
          Row(
            children: [
              _RouteInfoChip(
                icon: Icons.straighten_rounded,
                label: route.formattedDistance,
              ),
              const SizedBox(width: 10),
              _RouteInfoChip(
                icon: Icons.schedule_rounded,
                label: route.formattedDuration,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _RouteInfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF4A90FF).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF4A90FF).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF4A90FF), size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
