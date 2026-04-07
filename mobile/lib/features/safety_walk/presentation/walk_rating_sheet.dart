import 'package:flutter/material.dart';
import 'package:londonsnaps/features/safety_walk/models/safety_walk_models.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';

/// Colors for walk rating components
class _WalkRatingColors {
  static const background = Color(0xFF1C1C1E);
  static const card = Color(0xFF2C2C2E);
  static const starYellow = Color(0xFFFFC107);
  static const textSecondary = Color(0xFF8E8E93);
  static const primaryColor = Color(0xFF6366F1);
}

/// Standalone rating sheet for walk history
/// Can be shown separately from walk completion
class WalkRatingSheet extends StatefulWidget {
  final SafetyWalkUser companion;
  final String walkId;
  final Function(int score, String? comment) onSubmitRating;
  final VoidCallback onSkip;

  const WalkRatingSheet({
    super.key,
    required this.companion,
    required this.walkId,
    required this.onSubmitRating,
    required this.onSkip,
  });

  @override
  State<WalkRatingSheet> createState() => _WalkRatingSheetState();
}

class _WalkRatingSheetState extends State<WalkRatingSheet> {
  int _selectedRating = 0;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
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
    return Container(
      decoration: const BoxDecoration(
        color: _WalkRatingColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _WalkRatingColors.primaryColor.withValues(alpha: 0.15),
                      _WalkRatingColors.primaryColor.withValues(alpha: 0.05),
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
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Companion info
                    AvatarWidget(
                      avatarUrl: widget.companion.avatarUrl,
                      radius: 36,
                      showBorder: true,
                      borderColor: _WalkRatingColors.primaryColor,
                      borderWidth: 2,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.companion.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (widget.companion.universityName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.companion.universityName!,
                        style: const TextStyle(
                          color: _WalkRatingColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'How was your walk together?',
                      style: TextStyle(
                        color: _WalkRatingColors.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),

              // Rating section
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: AnimatedScale(
                              scale: starIndex <= _selectedRating ? 1.1 : 1.0,
                              duration: const Duration(milliseconds: 150),
                              child: Icon(
                                starIndex <= _selectedRating
                                    ? Icons.star
                                    : Icons.star_border,
                                color: starIndex <= _selectedRating
                                    ? _WalkRatingColors.starYellow
                                    : _WalkRatingColors.textSecondary,
                                size: 44,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    // Rating label
                    Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          _getRatingLabel(_selectedRating),
                          key: ValueKey(_selectedRating),
                          style: TextStyle(
                            color: _selectedRating > 0
                                ? _WalkRatingColors.starYellow
                                : _WalkRatingColors.textSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Comment field
                    const Text(
                      'Add a comment (optional)',
                      style: TextStyle(
                        color: _WalkRatingColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _commentController,
                      maxLines: 3,
                      maxLength: 250,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _WalkRatingColors.card,
                        hintText: 'Share your experience...',
                        hintStyle: const TextStyle(
                          color: _WalkRatingColors.textSecondary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: _WalkRatingColors.primaryColor,
                          ),
                        ),
                        contentPadding: const EdgeInsets.all(14),
                        counterStyle: const TextStyle(
                          color: _WalkRatingColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      cursorColor: _WalkRatingColors.primaryColor,
                    ),
                  ],
                ),
              ),

              // Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  children: [
                    // Submit button
                    GestureDetector(
                      onTap: _selectedRating > 0 && !_isSubmitting
                          ? _submitRating
                          : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: _selectedRating > 0
                              ? _WalkRatingColors.primaryColor
                              : _WalkRatingColors.card,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: _selectedRating > 0
                              ? [
                                  BoxShadow(
                                    color: _WalkRatingColors.primaryColor
                                        .withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
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
                                        : _WalkRatingColors.textSecondary,
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
                            color: _WalkRatingColors.textSecondary,
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

  String _getRatingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Great';
      case 5:
        return 'Excellent!';
      default:
        return 'Tap to rate';
    }
  }
}

/// Simplified star rating widget that can be used inline
class StarRatingWidget extends StatelessWidget {
  final int rating;
  final int maxRating;
  final double size;
  final ValueChanged<int>? onRatingChanged;
  final bool isInteractive;

  const StarRatingWidget({
    super.key,
    required this.rating,
    this.maxRating = 5,
    this.size = 24,
    this.onRatingChanged,
    this.isInteractive = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(maxRating, (index) {
        final starIndex = index + 1;
        return GestureDetector(
          onTap: isInteractive && onRatingChanged != null
              ? () => onRatingChanged!(starIndex)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              starIndex <= rating ? Icons.star : Icons.star_border,
              color: starIndex <= rating
                  ? _WalkRatingColors.starYellow
                  : _WalkRatingColors.textSecondary,
              size: size,
            ),
          ),
        );
      }),
    );
  }
}

/// Displays a user's average rating
class AverageRatingDisplay extends StatelessWidget {
  final double averageRating;
  final int totalRatings;

  const AverageRatingDisplay({
    super.key,
    required this.averageRating,
    required this.totalRatings,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.star,
          color: _WalkRatingColors.starYellow,
          size: 18,
        ),
        const SizedBox(width: 4),
        Text(
          averageRating.toStringAsFixed(1),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '($totalRatings)',
          style: const TextStyle(
            color: _WalkRatingColors.textSecondary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
