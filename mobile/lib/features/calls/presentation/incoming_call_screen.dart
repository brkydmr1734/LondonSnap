import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/calls/providers/call_provider.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';

/// Premium incoming call screen — Snapchat-style
class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with TickerProviderStateMixin {
  final CallProvider _callProvider = CallProvider();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _ringController;
  late Animation<double> _ringAnimation;
  late AnimationController _slideController;

  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _callProvider.addListener(_onCallStateChanged);

    // Avatar pulse
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Ring ripples
    _ringController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat();
    _ringAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeOut),
    );

    // Slide-up entrance
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();

    // Auto-dismiss after 30s
    _dismissTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _callProvider.state == CallState.ringingIncoming) {
        _callProvider.declineCall();
        _navigateBack();
      }
    });
  }

  void _onCallStateChanged() {
    if (!mounted) return;

    if (_callProvider.state == CallState.connecting ||
        _callProvider.state == CallState.active) {
      context.go('/active-call');
    } else if (_callProvider.state == CallState.idle ||
        _callProvider.state == CallState.ended) {
      _navigateBack();
    }
  }

  void _navigateBack() {
    if (Navigator.of(context).canPop()) {
      context.pop();
    } else {
      context.go('/chats');
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _callProvider.removeListener(_onCallStateChanged);
    _pulseController.dispose();
    _ringController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _accept() => _callProvider.acceptCall();

  void _decline() {
    _callProvider.declineCall();
    _navigateBack();
  }

  @override
  Widget build(BuildContext context) {
    final participant = _callProvider.remoteParticipant;
    final isVideo = _callProvider.isVideoCall;
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
              Color(0xFF0F3460),
              Color(0xFF1A1A2E),
            ],
            stops: [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),

              // ── Call type badge ──
              _buildCallTypeBadge(isVideo),

              const Spacer(flex: 2),

              // ── Avatar with ring animation ──
              _buildAvatarSection(participant),

              const SizedBox(height: 28),

              // ── Name ──
              Text(
                participant?.name ?? 'Unknown',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),

              // ── Status ──
              Text(
                isVideo ? 'Video calling you...' : 'Calling you...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),

              const Spacer(flex: 3),

              // ── Accept / Decline buttons ──
              SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.5),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: _slideController,
                  curve: Curves.easeOutCubic,
                )),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Decline
                      _IncomingCallAction(
                        icon: Icons.call_end_rounded,
                        gradient: const [Color(0xFFEF4444), Color(0xFFDC2626)],
                        label: 'Decline',
                        onTap: _decline,
                      ),
                      // Accept
                      _IncomingCallAction(
                        icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                        gradient: const [Color(0xFF34D399), Color(0xFF10B981)],
                        label: 'Accept',
                        onTap: _accept,
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: mq.padding.bottom + 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallTypeBadge(bool isVideo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
            color: AppTheme.primaryColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            isVideo ? 'Incoming video call' : 'Incoming voice call',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarSection(CallParticipant? participant) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Animated ripple rings
        AnimatedBuilder(
          animation: _ringAnimation,
          builder: (context, _) {
            return Stack(
              alignment: Alignment.center,
              children: [
                _buildRipple(_ringAnimation.value),
                _buildRipple((_ringAnimation.value + 0.33) % 1.0),
                _buildRipple((_ringAnimation.value + 0.66) % 1.0),
              ],
            );
          },
        ),
        // Pulsing avatar
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, _) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withValues(alpha: 0.5),
                      AppTheme.secondaryColor.withValues(alpha: 0.5),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
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
    );
  }

  Widget _buildRipple(double progress) {
    return Container(
      width: 180 + (80 * progress),
      height: 180 + (80 * progress),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.25 * (1 - progress)),
          width: 2,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════

class _IncomingCallAction extends StatelessWidget {
  final IconData icon;
  final List<Color> gradient;
  final String label;
  final VoidCallback onTap;

  const _IncomingCallAction({
    required this.icon,
    required this.gradient,
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
              gradient: LinearGradient(colors: gradient),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: gradient.first.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
