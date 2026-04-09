import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/calls/providers/call_provider.dart';
import 'package:londonsnaps/features/calls/services/webrtc_service.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';

/// Premium active call screen — Snapchat-style voice & video calls
class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen>
    with TickerProviderStateMixin {
  final CallProvider _callProvider = CallProvider();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _fadeController;

  // Draggable PiP state
  Offset _pipOffset = const Offset(16, 100);
  bool _showControls = true;
  Timer? _hideControlsTimer;
  bool _renderersInitialized = false;
  bool _hasNavigatedAway = false;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _callProvider.addListener(_onCallStateChanged);

    // Pulse animation for voice call avatar
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Fade controller for controls
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
      value: 1.0,
    );

    _resetHideTimer();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _renderersInitialized = true;
    _syncRenderers();
  }

  /// Sync renderer srcObjects with current WebRTC streams
  void _syncRenderers() {
    if (!_renderersInitialized || !mounted) return;

    final local = _callProvider.webrtcService.localStream;
    final remote = _callProvider.webrtcService.remoteStream;

    if (local != null && _localRenderer.srcObject != local) {
      _localRenderer.srcObject = local;
    }
    if (remote != null && _remoteRenderer.srcObject != remote) {
      _remoteRenderer.srcObject = remote;
    }
  }

  void _onCallStateChanged() {
    if (!mounted) return;
    _syncRenderers();
    setState(() {});

    // Show error snackbar
    if (_callProvider.errorMessage != null) {
      final msg = _callProvider.errorMessage!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      });
    }

    // Navigate back when call ends (with guard against double-navigation)
    if (!_hasNavigatedAway &&
        (_callProvider.state == CallState.idle ||
         _callProvider.state == CallState.ended)) {
      _hasNavigatedAway = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (Navigator.of(context).canPop()) {
            context.pop();
          } else {
            context.go('/chats');
          }
        }
      });
    }
  }

  void _resetHideTimer() {
    _hideControlsTimer?.cancel();
    if (_callProvider.isVideoCall && _callProvider.state == CallState.active) {
      _hideControlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _showControls) {
          setState(() => _showControls = false);
          _fadeController.reverse();
        }
      });
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _fadeController.forward();
      _resetHideTimer();
    } else {
      _fadeController.reverse();
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _callProvider.removeListener(_onCallStateChanged);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = _callProvider.isVideoCall;
    final state = _callProvider.state;
    final participant = _callProvider.remoteParticipant;
    final mediaQuery = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: isVideo ? _toggleControls : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background ──
            if (isVideo)
              _buildVideoBackground(state)
            else
              _buildVoiceBackground(participant),

            // ── Top safe area bar ──
            _buildTopBar(state, participant, mediaQuery),

            // ── Local video PiP (video calls) ──
            if (isVideo) _buildLocalVideoPiP(mediaQuery),

            // ── Connection quality badge ──
            if (state == CallState.active) _buildQualityBadge(mediaQuery),

            // ── Bottom controls ──
            _buildBottomControls(isVideo, mediaQuery),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VIDEO BACKGROUND
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildVideoBackground(CallState state) {
    final remoteStream = _callProvider.webrtcService.remoteStream;
    final hasRemote = remoteStream != null && state == CallState.active;

    if (hasRemote) {
      return RTCVideoView(
        _remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        mirror: false,
      );
    }

    // Show local preview as blurred background while connecting
    final localStream = _callProvider.webrtcService.localStream;
    if (localStream != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          RTCVideoView(
            _localRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            mirror: _callProvider.isFrontCamera,
          ),
          // Frosted glass overlay
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.black.withValues(alpha: 0.4)),
          ),
          _buildConnectingOverlay(),
        ],
      );
    }

    return Container(
      color: Colors.black,
      child: _buildConnectingOverlay(),
    );
  }

  Widget _buildConnectingOverlay() {
    final isRinging = _callProvider.state == CallState.ringingOutgoing;
    final participant = _callProvider.remoteParticipant;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 2),
            ),
            child: AvatarWidget(
              avatarUrl: participant?.avatarUrl,
              radius: 50,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            participant?.name ?? 'Unknown',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isRinging ? 'Ringing...' : 'Connecting...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VOICE CALL BACKGROUND
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildVoiceBackground(CallParticipant? participant) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
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
            const Spacer(flex: 2),
            // Pulsing avatar
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withValues(alpha: 0.3),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primaryColor.withValues(alpha: 0.6),
                            AppTheme.secondaryColor.withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                      child: AvatarWidget(
                        avatarUrl: participant?.avatarUrl,
                        radius: 80,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              participant?.name ?? 'Unknown',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _callProvider.state == CallState.connecting
                  ? 'Connecting...'
                  : _callProvider.state == CallState.ringingOutgoing
                      ? 'Ringing...'
                      : _callProvider.formattedDuration,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 18,
                fontWeight: FontWeight.w400,
              ),
            ),
            const Spacer(flex: 3),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOP BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTopBar(CallState state, CallParticipant? participant, MediaQueryData mq) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: EdgeInsets.only(
            top: mq.padding.top + 8,
            left: 16,
            right: 16,
            bottom: 12,
          ),
          decoration: _callProvider.isVideoCall
              ? BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                )
              : null,
          child: Row(
            children: [
              // Call info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_callProvider.isVideoCall)
                      Text(
                        participant?.name ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        // Status dot
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: state == CallState.active
                                ? const Color(0xFF34D399)
                                : state == CallState.ringingOutgoing
                                    ? AppTheme.primaryColor
                                    : const Color(0xFFFBBF24),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          state == CallState.connecting
                              ? 'Connecting...'
                              : state == CallState.ringingOutgoing
                                  ? 'Ringing...'
                                  : _callProvider.isVideoCall
                                      ? _callProvider.formattedDuration
                                      : '',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Flip camera (video only)
              if (_callProvider.isVideoCall && state == CallState.active)
                _buildMiniButton(
                  icon: Icons.flip_camera_ios_rounded,
                  onTap: () => _callProvider.switchCamera(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOCAL VIDEO PiP
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLocalVideoPiP(MediaQueryData mq) {
    final localStream = _callProvider.webrtcService.localStream;
    final hasLocal = localStream != null && _callProvider.isVideoEnabled;

    if (!hasLocal) return const SizedBox.shrink();

    final pipW = 110.0;
    final pipH = 155.0;

    return Positioned(
      left: _pipOffset.dx,
      top: _pipOffset.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _pipOffset += d.delta;
            final maxX = mq.size.width - pipW - 8;
            final maxY = mq.size.height - pipH - 8;
            _pipOffset = Offset(
              _pipOffset.dx.clamp(8.0, maxX),
              _pipOffset.dy.clamp(mq.padding.top + 50, maxY),
            );
          });
        },
        onPanEnd: (_) => _snapPipToEdge(mq, pipW),
        child: AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.6,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: pipW,
            height: pipH,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: RTCVideoView(
                _localRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                mirror: _callProvider.isFrontCamera,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Snap PiP to nearest horizontal edge
  void _snapPipToEdge(MediaQueryData mq, double pipW) {
    final center = _pipOffset.dx + pipW / 2;
    final screenCenter = mq.size.width / 2;
    final targetX = center < screenCenter ? 12.0 : mq.size.width - pipW - 12;
    setState(() {
      _pipOffset = Offset(targetX, _pipOffset.dy);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QUALITY BADGE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildQualityBadge(MediaQueryData mq) {
    final q = _callProvider.connectionQuality;
    if (q == ConnectionQuality.excellent) return const SizedBox.shrink();

    Color color;
    String label;
    IconData icon;
    switch (q) {
      case ConnectionQuality.good:
        color = const Color(0xFFFBBF24);
        label = 'Weak';
        icon = Icons.signal_cellular_alt_2_bar;
        break;
      case ConnectionQuality.poor:
        color = const Color(0xFFF87171);
        label = 'Poor';
        icon = Icons.signal_cellular_alt_1_bar;
        break;
      case ConnectionQuality.disconnected:
        color = const Color(0xFFEF4444);
        label = 'Lost';
        icon = Icons.signal_cellular_off;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Positioned(
      top: mq.padding.top + 60,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTTOM CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomControls(bool isVideo, MediaQueryData mq) {
    final isActive = _callProvider.state == CallState.active ||
        _callProvider.state == CallState.connecting;
    final isRinging = _callProvider.state == CallState.ringingOutgoing;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: EdgeInsets.only(
            top: 20,
            bottom: mq.padding.bottom + 20,
            left: 24,
            right: 24,
          ),
          decoration: isVideo
              ? BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                )
              : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mute
              _CallControlButton(
                icon: _callProvider.isMuted
                    ? Icons.mic_off_rounded
                    : Icons.mic_rounded,
                label: _callProvider.isMuted ? 'Unmute' : 'Mute',
                isActive: _callProvider.isMuted,
                onTap: isActive
                    ? () {
                        _callProvider.toggleMute();
                        setState(() {});
                      }
                    : null,
              ),

              // Video toggle (video calls only)
              if (isVideo)
                _CallControlButton(
                  icon: _callProvider.isVideoEnabled
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  label: _callProvider.isVideoEnabled ? 'Camera' : 'Camera Off',
                  isActive: !_callProvider.isVideoEnabled,
                  onTap: isActive
                      ? () {
                          _callProvider.toggleVideo();
                          setState(() {});
                        }
                      : null,
                ),

              // End call
              GestureDetector(
                onTap: _endCall,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    isRinging ? Icons.call_end_rounded : Icons.call_end_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),

              // Speaker (always available)
              _CallControlButton(
                icon: _callProvider.isSpeakerOn
                    ? Icons.volume_up_rounded
                    : Icons.volume_down_rounded,
                label: 'Speaker',
                isActive: _callProvider.isSpeakerOn,
                onTap: isActive
                    ? () async {
                        try { await _callProvider.toggleSpeaker(); } catch (_) {}
                        if (mounted) setState(() {});
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _endCall() {
    if (_callProvider.state == CallState.ringingOutgoing) {
      _callProvider.cancelCall();
    } else {
      _callProvider.endCall();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMiniButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CALL CONTROL BUTTON
// ═══════════════════════════════════════════════════════════════════════════════

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final opacity = enabled ? 1.0 : 0.4;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: opacity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isActive ? Colors.black : Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
