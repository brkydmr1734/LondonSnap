import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/calls/providers/call_provider.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';

/// Incoming call screen with accept/decline options
class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with TickerProviderStateMixin {
  final CallProvider _callProvider = CallProvider();
  late AnimationController _pulseController;
  late AnimationController _ringController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _ringAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _callProvider.addListener(_onCallStateChanged);

    // Pulse animation for avatar
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Ring animation for outer circles
    _ringController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _ringAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeOut),
    );

    // Auto-dismiss after 30 seconds (call will be marked as missed)
    _dismissTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _callProvider.state == CallState.ringingIncoming) {
        _callProvider.declineCall();
        if (Navigator.of(context).canPop()) {
          context.pop();
        } else {
          context.go('/chats');
        }
      }
    });
  }

  void _onCallStateChanged() {
    if (!mounted) return;

    // Navigate based on state changes
    if (_callProvider.state == CallState.connecting ||
        _callProvider.state == CallState.active) {
      // Go to active call screen
      context.go('/active-call');
    } else if (_callProvider.state == CallState.idle ||
        _callProvider.state == CallState.ended) {
      // Call ended or missed, go back
      if (Navigator.of(context).canPop()) {
        context.pop();
      } else {
        context.go('/chats');
      }
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _callProvider.removeListener(_onCallStateChanged);
    _pulseController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  void _acceptCall() {
    _callProvider.acceptCall();
  }

  void _declineCall() {
    _callProvider.declineCall();
    if (Navigator.of(context).canPop()) {
      context.pop();
    } else {
      context.go('/chats');
    }
  }

  @override
  Widget build(BuildContext context) {
    final participant = _callProvider.remoteParticipant;
    final isVideo = _callProvider.isVideoCall;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.primaryColor.withValues(alpha: 0.3),
              AppTheme.backgroundColor,
              AppTheme.backgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 60),

              // Call type indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isVideo ? Icons.videocam : Icons.phone,
                      color: AppTheme.primaryColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isVideo ? 'Incoming video call' : 'Incoming voice call',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 1),

              // Caller avatar with pulse animation
              Stack(
                alignment: Alignment.center,
                children: [
                  // Animated rings
                  AnimatedBuilder(
                    animation: _ringAnimation,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // First ring
                          Container(
                            width: 180 + (60 * _ringAnimation.value),
                            height: 180 + (60 * _ringAnimation.value),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.3 * (1 - _ringAnimation.value),
                                ),
                                width: 2,
                              ),
                            ),
                          ),
                          // Second ring (delayed)
                          Container(
                            width: 180 + (60 * ((_ringAnimation.value + 0.5) % 1)),
                            height: 180 + (60 * ((_ringAnimation.value + 0.5) % 1)),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.3 * (1 - ((_ringAnimation.value + 0.5) % 1)),
                                ),
                                width: 2,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  // Avatar with pulse
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                AppTheme.primaryColor.withValues(alpha: 0.5),
                                AppTheme.secondaryColor.withValues(alpha: 0.5),
                              ],
                            ),
                          ),
                          child: AvatarWidget(
                            avatarUrl: participant?.avatarUrl,
                            radius: 70,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Caller name
              Text(
                participant?.name ?? 'Unknown',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 8),

              // Status text
              Text(
                isVideo ? 'is video calling you...' : 'is calling you...',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 16,
                ),
              ),

              const Spacer(flex: 2),

              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Decline button
                    _CallActionButton(
                      icon: Icons.call_end,
                      color: AppTheme.errorColor,
                      label: 'Decline',
                      onTap: _declineCall,
                    ),

                    // Accept button
                    _CallActionButton(
                      icon: isVideo ? Icons.videocam : Icons.call,
                      color: AppTheme.successColor,
                      label: 'Accept',
                      onTap: _acceptCall,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }
}

/// Call action button (accept/decline)
class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
