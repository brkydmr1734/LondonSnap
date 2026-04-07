import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:londonsnaps/features/safety_walk/models/safety_walk_models.dart';

/// Colors for SOS components
class _SOSColors {
  static const background = Color(0xFF1C1C1E);
  static const card = Color(0xFF2C2C2E);
  static const sosRed = Color(0xFFE63946);
  static const safetyGreen = Color(0xFF00C853);
  static const textSecondary = Color(0xFF8E8E93);
}

/// Large emergency SOS button with 3-second long press activation.
class SOSButton extends StatefulWidget {
  final VoidCallback onSOS;
  final double size;

  const SOSButton({
    super.key,
    required this.onSOS,
    this.size = 64,
  });

  @override
  State<SOSButton> createState() => _SOSButtonState();
}

class _SOSButtonState extends State<SOSButton>
    with TickerProviderStateMixin {
  static const _activationDuration = Duration(seconds: 3);
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _holdController;
  
  Timer? _hapticTimer;
  bool _isHolding = false;
  bool _sosTriggered = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _holdController = AnimationController(
      vsync: this,
      duration: _activationDuration,
    );
    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _hapticTimer?.cancel();
        _triggerSOS();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _holdController.dispose();
    _hapticTimer?.cancel();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_sosTriggered) return;
    
    setState(() {
      _isHolding = true;
    });

    // Start haptic feedback every second
    _hapticTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      HapticFeedback.heavyImpact();
    });

    // Use AnimationController for smooth progress (no setState jank)
    _holdController.forward(from: 0.0);

    // Initial haptic
    HapticFeedback.heavyImpact();
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_sosTriggered) return;
    _cancelHold();
    
    if (!_sosTriggered && _holdController.value < 1.0) {
      _showHoldHint();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_sosTriggered) return;
    _cancelHold();
  }

  void _cancelHold() {
    _holdController.reset();
    _hapticTimer?.cancel();
    
    setState(() {
      _isHolding = false;
    });
  }

  void _triggerSOS() {
    setState(() {
      _sosTriggered = true;
      _isHolding = false;
    });

    // Strong vibration pattern
    HapticFeedback.vibrate();
    
    widget.onSOS();
  }

  void _showHoldHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.white),
            SizedBox(width: 8),
            Text('Hold for 3 seconds to activate SOS'),
          ],
        ),
        backgroundColor: _SOSColors.sosRed.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _holdController]),
      builder: (_, child) {
        final scale = _sosTriggered ? 1.0 : _pulseAnimation.value;
        return Transform.scale(
          scale: _isHolding ? 1.1 : scale,
          child: child,
        );
      },
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: _sosTriggered 
                ? _SOSColors.safetyGreen 
                : _SOSColors.sosRed,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (_sosTriggered 
                    ? _SOSColors.safetyGreen 
                    : _SOSColors.sosRed).withValues(alpha: 0.5),
                blurRadius: 16,
                spreadRadius: 4,
              ),
            ],
          ),
          child: CustomPaint(
            painter: _SOSCountdownPainter(
              progress: _holdController.value,
              isHolding: _isHolding,
            ),
            child: Center(
              child: _sosTriggered
                  ? const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 28,
                    )
                  : const Text(
                      'SOS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Countdown ring painter for SOS button
class _SOSCountdownPainter extends CustomPainter {
  final double progress;
  final bool isHolding;

  _SOSCountdownPainter({
    required this.progress,
    required this.isHolding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isHolding || progress <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    
    // Background ring
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final sweepAngle = progress * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // Start from top
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SOSCountdownPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isHolding != isHolding;
  }
}

/// Bottom sheet shown after SOS is triggered
class SOSActivatedSheet extends StatelessWidget {
  final SafetyWalkLocation? companionLocation;
  final VoidCallback onCancel;
  final VoidCallback onImSafe;

  const SOSActivatedSheet({
    super.key,
    this.companionLocation,
    required this.onCancel,
    required this.onImSafe,
  });

  Future<void> _call999(BuildContext context) async {
    final uri = Uri.parse('tel:999');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Cannot place call. Please dial 999 manually.'),
              backgroundColor: _SOSColors.sosRed,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[SOS] Failed to call 999: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Cannot place call. Please dial 999 manually.'),
            backgroundColor: _SOSColors.sosRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _openInMaps() async {
    if (companionLocation == null) return;
    
    final lat = companionLocation!.latitude;
    final lng = companionLocation!.longitude;
    final uri = Uri.parse('https://maps.apple.com/?ll=$lat,$lng&q=Companion');
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showCancelConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _SOSColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Cancel SOS?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to cancel the emergency alert? This will notify your companion.',
          style: TextStyle(color: _SOSColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No, Keep Alert'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              onCancel();
            },
            style: TextButton.styleFrom(foregroundColor: _SOSColors.sosRed),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _SOSColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Red gradient header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _SOSColors.sosRed.withValues(alpha: 0.3),
                    _SOSColors.sosRed.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                  // Alert icon and title
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '🆘',
                        style: TextStyle(fontSize: 28),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Emergency Alert Sent',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your companion and trusted contacts have been notified',
                    style: TextStyle(
                      color: _SOSColors.textSecondary,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Companion location
                  if (companionLocation != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _SOSColors.card,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Companion\'s Last Known Location',
                            style: TextStyle(
                              color: _SOSColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: _SOSColors.sosRed,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${companionLocation!.latitude.toStringAsFixed(6)}, '
                                  '${companionLocation!.longitude.toStringAsFixed(6)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _openInMaps,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Open in Maps',
                                    style: TextStyle(
                                      color: Color(0xFF6366F1),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Call 999 button
                  GestureDetector(
                    onTap: () => _call999(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _SOSColors.sosRed,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: _SOSColors.sosRed.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone, color: Colors.white, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'Call 999',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // I'm Safe button
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      onImSafe();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _SOSColors.safetyGreen,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, color: Colors.white, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'I\'m Safe',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Cancel SOS
                  GestureDetector(
                    onTap: () => _showCancelConfirmation(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: const Text(
                        'Cancel SOS',
                        style: TextStyle(
                          color: _SOSColors.textSecondary,
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
    );
  }
}
