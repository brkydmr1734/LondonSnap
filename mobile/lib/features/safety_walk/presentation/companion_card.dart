import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:londonsnaps/features/safety_walk/models/safety_walk_models.dart';
import 'package:londonsnaps/features/safety_walk/widgets/safety_score_badge.dart';

/// Production-ready companion card with glassmorphic design,
/// animated selection, rating display, and walking time estimate.
class CompanionCard extends StatelessWidget {
  final SafetyWalkCompanion companion;
  final bool isSelected;
  final bool isInviting;
  final VoidCallback onTap;
  final VoidCallback onInvite;

  const CompanionCard({
    super.key,
    required this.companion,
    this.isSelected = false,
    this.isInviting = false,
    required this.onTap,
    required this.onInvite,
  });

  String get _friendshipIcon {
    return switch (companion.friendshipLevel) {
      'BEST' => '⭐',
      'CLOSE' => '💜',
      'SAME_UNIVERSITY' => '🎓',
      _ => '👋',
    };
  }

  String get _friendshipLabel {
    return switch (companion.friendshipLevel) {
      'BEST' => 'Best Friend',
      'CLOSE' => 'Close Friend',
      'SAME_UNIVERSITY' => companion.universityName ?? 'Uni Mate',
      _ => 'Friend',
    };
  }

  Color get _friendshipColor {
    return switch (companion.friendshipLevel) {
      'BEST' => const Color(0xFFFFC107),
      'CLOSE' => const Color(0xFFCE93D8),
      'SAME_UNIVERSITY' => const Color(0xFF64B5F6),
      _ => const Color(0xFF80CBC4),
    };
  }

  /// Estimate walking time to companion in minutes
  String get _walkingTime {
    // Average walking speed ~80m/min
    final mins = (companion.distance / 80).ceil();
    if (mins <= 1) return '<1 min walk';
    return '$mins min walk';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF2A2A2E),
                    const Color(0xFF1E3A4D).withValues(alpha: 0.6),
                  ],
                )
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2A2A2E), Color(0xFF232326)],
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00BFFF).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.06),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF00BFFF).withValues(alpha: 0.12),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Avatar
            _buildAvatar(),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          companion.user.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SafetyScoreBadge(
                        score: companion.safetyScore,
                        size: 28,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Tags row
                  Row(
                    children: [
                      _buildTag(
                        _friendshipIcon,
                        _friendshipLabel,
                        _friendshipColor,
                      ),
                      const SizedBox(width: 6),
                      _buildTag(
                        '📍',
                        companion.formattedDistance,
                        Colors.white.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 6),
                      _buildTag(
                        '🚶',
                        _walkingTime,
                        Colors.white.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // Invite button
            _buildInviteButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 9)),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return Stack(
      children: [
        // Avatar ring
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: companion.user.isOnline
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF00C853), Color(0xFF69F0AE)],
                  )
                : LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.15),
                      Colors.white.withValues(alpha: 0.08),
                    ],
                  ),
          ),
          padding: const EdgeInsets.all(2),
          child: ClipOval(
            child: _buildAvatarContent(),
          ),
        ),
        // Online dot
        if (companion.user.isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF00C853),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF2A2A2E), width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00C853).withValues(alpha: 0.4),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatarContent() {
    if (companion.user.avatarUrl != null &&
        companion.user.avatarUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: companion.user.avatarUrl!,
        fit: BoxFit.cover,
        placeholder: (_, _) => _avatarPlaceholder(),
        errorWidget: (_, _, _) => _avatarPlaceholder(),
      );
    }
    return _avatarPlaceholder();
  }

  Widget _avatarPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A3A3C), Color(0xFF2C2C2E)],
        ),
      ),
      child: Center(
        child: Text(
          companion.user.displayName.isNotEmpty
              ? companion.user.displayName[0].toUpperCase()
              : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildInviteButton() {
    return GestureDetector(
      onTap: isInviting ? null : onInvite,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: isInviting
              ? null
              : isSelected
                  ? const LinearGradient(
                      colors: [Color(0xFF00BFFF), Color(0xFF0091EA)],
                    )
                  : const LinearGradient(
                      colors: [Color(0xFFFF6B35), Color(0xFFE63946)],
                    ),
          color: isInviting ? Colors.grey.shade700 : null,
          borderRadius: BorderRadius.circular(12),
          boxShadow: !isInviting
              ? [
                  BoxShadow(
                    color: (isSelected
                            ? const Color(0xFF00BFFF)
                            : const Color(0xFFE63946))
                        .withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: isInviting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Text(
                isSelected ? 'Send' : 'Invite',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
