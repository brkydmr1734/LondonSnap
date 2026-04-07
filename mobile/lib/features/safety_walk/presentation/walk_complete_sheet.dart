import 'package:flutter/material.dart';
import 'package:londonsnaps/features/safety_walk/models/safety_walk_models.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';

/// Colors for walk completion components
class _WalkCompleteColors {
  static const background = Color(0xFF1C1C1E);
  static const card = Color(0xFF2C2C2E);
  static const safetyGreen = Color(0xFF00C853);
  static const starYellow = Color(0xFFFFC107);
  static const textSecondary = Color(0xFF8E8E93);
  static const primaryColor = Color(0xFF6366F1);
}

/// Bottom sheet shown when a walk is completed
class WalkCompleteSheet extends StatefulWidget {
  final SafetyWalk walk;
  final Function(int score, String? comment) onSubmitRating;
  final VoidCallback onSkip;

  const WalkCompleteSheet({
    super.key,
    required this.walk,
    required this.onSubmitRating,
    required this.onSkip,
  });

  @override
  State<WalkCompleteSheet> createState() => _WalkCompleteSheetState();
}

class _WalkCompleteSheetState extends State<WalkCompleteSheet> {
  int _selectedRating = 0;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  String get _formattedDuration {
    if (widget.walk.startedAt == null) return '--';
    
    final endTime = widget.walk.endedAt ?? DateTime.now();
    final duration = endTime.difference(widget.walk.startedAt!);
    
    if (duration.inMinutes < 60) {
      return '${duration.inMinutes} min';
    }
    final hours = duration.inHours;
    final mins = duration.inMinutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }

  String get _transportModeLabel {
    switch (widget.walk.transportMode.toUpperCase()) {
      case 'WALKING':
        return 'Walking';
      case 'BUS':
        return 'Bus';
      case 'TUBE':
        return 'Tube';
      case 'MIXED':
        return 'Mixed Transport';
      default:
        return 'Walking';
    }
  }

  IconData get _transportModeIcon {
    switch (widget.walk.transportMode.toUpperCase()) {
      case 'WALKING':
        return Icons.directions_walk;
      case 'BUS':
        return Icons.directions_bus;
      case 'TUBE':
        return Icons.subway;
      case 'MIXED':
        return Icons.transfer_within_a_station;
      default:
        return Icons.directions_walk;
    }
  }

  Future<void> _submitRating() async {
    if (_selectedRating == 0) return;
    
    setState(() => _isSubmitting = true);
    
    final comment = _commentController.text.trim().isNotEmpty
        ? _commentController.text.trim()
        : null;
    
    widget.onSubmitRating(_selectedRating, comment);
  }

  @override
  Widget build(BuildContext context) {
    final companion = widget.walk.companion ?? widget.walk.requester;

    return Container(
      decoration: const BoxDecoration(
        color: _WalkCompleteColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _WalkCompleteColors.safetyGreen.withValues(alpha: 0.2),
                      _WalkCompleteColors.safetyGreen.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    // Drag handle
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Success icon and title
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _WalkCompleteColors.safetyGreen.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _WalkCompleteColors.safetyGreen,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: _WalkCompleteColors.safetyGreen,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Walk Completed!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              // Stats
              Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _WalkCompleteColors.card,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      // Duration
                      Expanded(
                        child: _StatItem(
                          icon: Icons.timer_outlined,
                          label: 'Duration',
                          value: _formattedDuration,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Colors.white12,
                      ),
                      // Route type
                      Expanded(
                        child: _StatItem(
                          icon: _transportModeIcon,
                          label: 'Route',
                          value: _transportModeLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Rating section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Companion avatar
                        AvatarWidget(
                          avatarUrl: companion?.avatarUrl,
                          radius: 20,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Rate your companion:',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Star rating
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final starIndex = index + 1;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _selectedRating = starIndex);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              starIndex <= _selectedRating
                                  ? Icons.star
                                  : Icons.star_border,
                              color: starIndex <= _selectedRating
                                  ? _WalkCompleteColors.starYellow
                                  : _WalkCompleteColors.textSecondary,
                              size: 40,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 20),
                    // Comment field
                    const Text(
                      'Comment (optional):',
                      style: TextStyle(
                        color: _WalkCompleteColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _commentController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _WalkCompleteColors.card,
                        hintText: 'Share your experience...',
                        hintStyle: const TextStyle(
                          color: _WalkCompleteColors.textSecondary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: _WalkCompleteColors.primaryColor,
                          ),
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                      cursorColor: _WalkCompleteColors.primaryColor,
                    ),
                  ],
                ),
              ),

              // Buttons
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Submit button
                    GestureDetector(
                      onTap: _selectedRating > 0 && !_isSubmitting
                          ? _submitRating
                          : null,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: _selectedRating > 0
                              ? _WalkCompleteColors.primaryColor
                              : _WalkCompleteColors.card,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  'Submit Rating',
                                  style: TextStyle(
                                    color: _selectedRating > 0
                                        ? Colors.white
                                        : _WalkCompleteColors.textSecondary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Skip button
                    GestureDetector(
                      onTap: widget.onSkip,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: const Text(
                          'Skip',
                          style: TextStyle(
                            color: _WalkCompleteColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single stat item for the walk summary
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          color: _WalkCompleteColors.textSecondary,
          size: 22,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: _WalkCompleteColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
