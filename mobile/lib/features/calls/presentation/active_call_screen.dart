import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/calls/providers/call_provider.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';

/// Active call screen for voice and video calls
class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen>
    with SingleTickerProviderStateMixin {
  final CallProvider _callProvider = CallProvider();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Draggable local video position
  Offset _localVideoPosition = const Offset(16, 100);
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _callProvider.addListener(_onCallStateChanged);

    // Pulse animation for audio call avatar
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    // Set up stream listeners
    _updateRenderers();
  }

  void _updateRenderers() {
    final localStream = _callProvider.webrtcService.localStream;
    final remoteStream = _callProvider.webrtcService.remoteStream;

    if (localStream != null) {
      _localRenderer.srcObject = localStream;
    }
    if (remoteStream != null) {
      _remoteRenderer.srcObject = remoteStream;
    }
  }

  void _onCallStateChanged() {
    if (!mounted) return;

    // Update renderers when streams change
    _updateRenderers();
    setState(() {});

    // Show error if any
    if (_callProvider.errorMessage != null) {
      final msg = _callProvider.errorMessage!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red),
          );
        }
      });
    }

    // Navigate back when call ends
    if (_callProvider.state == CallState.idle ||
        _callProvider.state == CallState.ended) {
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

  @override
  void dispose() {
    _callProvider.removeListener(_onCallStateChanged);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _endCall() {
    _callProvider.endCall();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = _callProvider.isVideoCall;
    final state = _callProvider.state;
    final participant = _callProvider.remoteParticipant;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: GestureDetector(
        onTap: isVideo ? _toggleControls : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Main content based on call type
            if (isVideo)
              _buildVideoCallView()
            else
              _buildAudioCallView(participant),

            // Top bar with call info
            _buildTopBar(state, participant),

            // Local video (PiP) for video calls
            if (isVideo && _callProvider.isVideoEnabled)
              _buildLocalVideo(),

            // Bottom control bar
            if (_showControls) _buildControlBar(isVideo),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoCallView() {
    final remoteStream = _callProvider.webrtcService.remoteStream;

    if (remoteStream == null ||
        _callProvider.state == CallState.connecting ||
        _callProvider.state == CallState.ringingOutgoing) {
      return _buildConnectingView();
    }

    return RTCVideoView(
      _remoteRenderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      mirror: false,
    );
  }

  Widget _buildAudioCallView(CallParticipant? participant) {
    return Container(
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated avatar
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 200 * _pulseAnimation.value,
                height: 200 * _pulseAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withValues(alpha: 0.3),
                      AppTheme.secondaryColor.withValues(alpha: 0.3),
                    ],
                  ),
                ),
                child: Center(
                  child: AvatarWidget(
                    avatarUrl: participant?.avatarUrl,
                    radius: 70,
                  ),
                ),
              );
            },
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

          // Call status/duration
          Text(
            _callProvider.state == CallState.connecting
                ? 'Connecting...'
                : _callProvider.state == CallState.ringingOutgoing
                    ? 'Ringing...'
                    : _callProvider.formattedDuration,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingView() {
    final isRinging = _callProvider.state == CallState.ringingOutgoing;
    return Container(
      color: AppTheme.backgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              color: AppTheme.primaryColor,
              strokeWidth: 3,
            ),
            const SizedBox(height: 24),
            Text(
              isRinging ? 'Ringing...' : 'Connecting...',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(CallState state, CallParticipant? participant) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            bottom: 16,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.7),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      participant?.name ?? 'Unknown',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: state == CallState.active
                                ? AppTheme.successColor
                                : state == CallState.ringingOutgoing
                                    ? AppTheme.primaryColor
                                    : AppTheme.warningColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          state == CallState.connecting
                              ? 'Connecting...'
                              : state == CallState.ringingOutgoing
                                  ? 'Ringing...'
                                  : _callProvider.formattedDuration,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Switch camera button (video calls only)
              if (_callProvider.isVideoCall)
                IconButton(
                  onPressed: _callProvider.switchCamera,
                  icon: const Icon(Icons.flip_camera_ios),
                  color: AppTheme.textPrimary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocalVideo() {
    return Positioned(
      left: _localVideoPosition.dx,
      top: _localVideoPosition.dy,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              _localVideoPosition += details.delta;
              // Keep within screen bounds
              final maxX = MediaQuery.of(context).size.width - 130;
              final maxY = MediaQuery.of(context).size.height - 190;
              _localVideoPosition = Offset(
                _localVideoPosition.dx.clamp(8, maxX),
                _localVideoPosition.dy.clamp(100, maxY),
              );
            });
          },
          child: Container(
            width: 120,
            height: 170,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.surfaceColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
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

  Widget _buildControlBar(bool isVideo) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: EdgeInsets.only(
            top: 24,
            bottom: MediaQuery.of(context).padding.bottom + 24,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.7),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mute button
              _ControlButton(
                icon: _callProvider.isMuted ? Icons.mic_off : Icons.mic,
                label: _callProvider.isMuted ? 'Unmute' : 'Mute',
                isActive: _callProvider.isMuted,
                onTap: () {
                  _callProvider.toggleMute();
                  setState(() {});
                },
              ),

              // Speaker button (audio calls only)
              if (!isVideo)
                _ControlButton(
                  icon: _callProvider.isSpeakerOn
                      ? Icons.volume_up
                      : Icons.volume_down,
                  label: 'Speaker',
                  isActive: _callProvider.isSpeakerOn,
                  onTap: () async {
                    await _callProvider.toggleSpeaker();
                    setState(() {});
                  },
                ),

              // Video toggle (video calls only)
              if (isVideo)
                _ControlButton(
                  icon: _callProvider.isVideoEnabled
                      ? Icons.videocam
                      : Icons.videocam_off,
                  label: _callProvider.isVideoEnabled ? 'Stop Video' : 'Start Video',
                  isActive: !_callProvider.isVideoEnabled,
                  onTap: () {
                    _callProvider.toggleVideo();
                    setState(() {});
                  },
                ),

              // End call button
              GestureDetector(
                onTap: _endCall,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AppTheme.errorColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Control button widget
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive
                  ? AppTheme.textPrimary
                  : AppTheme.surfaceColor.withValues(alpha: 0.8),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? AppTheme.backgroundColor : AppTheme.textPrimary,
              size: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
