import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:londonsnaps/core/config/app_config.dart';

/// Connection quality levels
enum ConnectionQuality { excellent, good, poor, disconnected }

/// WebRTC service for managing peer connections, media streams, and ICE candidates
class WebRTCService {
  // ICE servers - will be overridden by fetched credentials
  List<Map<String, dynamic>> _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // Callbacks for events
  Function(RTCIceCandidate)? onIceCandidate;
  Function(MediaStream)? onRemoteStream;
  Function(RTCPeerConnectionState)? onConnectionStateChange;
  Function(RTCIceConnectionState)? onIceConnectionStateChange;

  // State
  bool _isMuted = false;
  bool _isVideoEnabled = true;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;

  // Connection quality tracking
  ConnectionQuality _connectionQuality = ConnectionQuality.excellent;
  Timer? _statsTimer;
  int _prevBytesReceived = 0;
  ConnectionQuality get connectionQuality => _connectionQuality;
  Function(ConnectionQuality)? onConnectionQualityChange;

  // Track whether remote description has been set (for ICE candidate queuing)
  bool _remoteDescriptionSet = false;
  bool get remoteDescriptionSet => _remoteDescriptionSet;

  bool get isMuted => _isMuted;
  bool get isVideoEnabled => _isVideoEnabled;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isFrontCamera => _isFrontCamera;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  RTCPeerConnection? get peerConnection => _peerConnection;

  /// Set ICE servers (called with fetched credentials from backend)
  void setIceServers(List<Map<String, dynamic>> servers) {
    _iceServers = servers;
  }

  /// Initialize WebRTC peer connection
  Future<void> initialize({required bool isVideoCall}) async {
    // Dispose any existing connection first
    await dispose();

    try {
      final config = {
        'iceServers': _iceServers,
        'sdpSemantics': 'unified-plan',
      };

      final constraints = {
        'mandatory': {},
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
        ],
      };

      _peerConnection = await createPeerConnection(config, constraints);

      // Get user media
      await _getUserMedia(isVideoCall);

      // Add local tracks to peer connection
      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          await _peerConnection!.addTrack(track, _localStream!);
        }
      }

      // Setup event listeners
      _setupPeerConnectionListeners();

      if (AppConfig.isDev) debugPrint('[WebRTC] Initialized successfully');
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[WebRTC] Initialize error: $e');
      rethrow;
    }
  }

  /// Get user media (audio and optionally video)
  Future<void> _getUserMedia(bool isVideoCall) async {
    try {
      final mediaConstraints = {
        'audio': true,
        'video': isVideoCall
            ? {
                'facingMode': _isFrontCamera ? 'user' : 'environment',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);

      // Set default speaker mode
      if (!isVideoCall) {
        await Helper.setSpeakerphoneOn(false);
        _isSpeakerOn = false;
      }

      if (AppConfig.isDev) debugPrint('[WebRTC] Got user media');
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[WebRTC] getUserMedia error: $e');
      rethrow;
    }
  }

  /// Setup peer connection event listeners
  void _setupPeerConnectionListeners() {
    _peerConnection?.onIceCandidate = (candidate) {
      if (AppConfig.isDev) debugPrint('[WebRTC] ICE candidate: ${candidate.candidate}');
      onIceCandidate?.call(candidate);
    };

    _peerConnection?.onIceConnectionState = (state) {
      if (AppConfig.isDev) debugPrint('[WebRTC] ICE connection state: $state');
      onIceConnectionStateChange?.call(state);
    };

    _peerConnection?.onConnectionState = (state) {
      if (AppConfig.isDev) debugPrint('[WebRTC] Connection state: $state');
      onConnectionStateChange?.call(state);
    };

    _peerConnection?.onTrack = (event) {
      if (AppConfig.isDev) debugPrint('[WebRTC] Track received: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);
      }
    };

    _peerConnection?.onAddStream = (stream) {
      if (AppConfig.isDev) debugPrint('[WebRTC] Stream added');
      _remoteStream = stream;
      onRemoteStream?.call(stream);
    };
  }

  /// Start monitoring connection quality via getStats()
  void startQualityMonitoring() {
    _statsTimer?.cancel();
    _prevBytesReceived = 0;
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkConnectionQuality());
  }

  /// Stop monitoring
  void stopQualityMonitoring() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  Future<void> _checkConnectionQuality() async {
    if (_peerConnection == null) return;

    try {
      final stats = await _peerConnection!.getStats();
      double? roundTripTime;
      double? packetLossPercent;
      int currentBytesReceived = 0;

      for (final report in stats) {
        final values = report.values;
        if (report.type == 'candidate-pair' && values['state'] == 'succeeded') {
          roundTripTime = (values['currentRoundTripTime'] as num?)?.toDouble();
        }
        if (report.type == 'inbound-rtp' && values['kind'] == 'audio') {
          final lost = (values['packetsLost'] as num?)?.toInt() ?? 0;
          final received = (values['packetsReceived'] as num?)?.toInt() ?? 0;
          if (received + lost > 0) {
            packetLossPercent = (lost / (received + lost)) * 100;
          }
        }
        if (report.type == 'inbound-rtp') {
          currentBytesReceived += (values['bytesReceived'] as num?)?.toInt() ?? 0;
        }
      }

      // Determine quality level
      ConnectionQuality newQuality;
      if (currentBytesReceived <= _prevBytesReceived && _prevBytesReceived > 0) {
        // No data flowing
        newQuality = ConnectionQuality.disconnected;
      } else if (roundTripTime != null && roundTripTime > 0.5) {
        newQuality = ConnectionQuality.poor;
      } else if (packetLossPercent != null && packetLossPercent > 10) {
        newQuality = ConnectionQuality.poor;
      } else if (roundTripTime != null && roundTripTime > 0.2) {
        newQuality = ConnectionQuality.good;
      } else if (packetLossPercent != null && packetLossPercent > 3) {
        newQuality = ConnectionQuality.good;
      } else {
        newQuality = ConnectionQuality.excellent;
      }

      _prevBytesReceived = currentBytesReceived;

      if (newQuality != _connectionQuality) {
        _connectionQuality = newQuality;
        onConnectionQualityChange?.call(newQuality);
        if (AppConfig.isDev) debugPrint('[WebRTC] Quality: $newQuality');
      }
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[WebRTC] Stats error: $e');
    }
  }

  /// Create SDP offer (for call initiator)
  Future<RTCSessionDescription> createOffer() async {
    try {
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await _peerConnection!.setLocalDescription(offer);
      if (AppConfig.isDev) debugPrint('[WebRTC] Created offer');
      return offer;
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[WebRTC] createOffer error: $e');
      rethrow;
    }
  }

  /// Create SDP answer (for call receiver)
  Future<RTCSessionDescription> createAnswer() async {
    try {
      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await _peerConnection!.setLocalDescription(answer);
      if (AppConfig.isDev) debugPrint('[WebRTC] Created answer');
      return answer;
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[WebRTC] createAnswer error: $e');
      rethrow;
    }
  }

  /// Set remote description (SDP from other peer)
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    try {
      await _peerConnection!.setRemoteDescription(description);
      _remoteDescriptionSet = true;
      if (AppConfig.isDev) debugPrint('[WebRTC] Set remote description: ${description.type}');
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[WebRTC] setRemoteDescription error: $e');
      rethrow;
    }
  }

  /// Add ICE candidate from remote peer
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    try {
      await _peerConnection!.addCandidate(candidate);
      if (AppConfig.isDev) debugPrint('[WebRTC] Added ICE candidate');
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[WebRTC] addIceCandidate error: $e');
    }
  }

  /// Toggle microphone mute
  void toggleMute() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        _isMuted = !_isMuted;
        audioTracks[0].enabled = !_isMuted;
        if (AppConfig.isDev) debugPrint('[WebRTC] Mute: $_isMuted');
      }
    }
  }

  /// Toggle video on/off
  void toggleVideo() {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        _isVideoEnabled = !_isVideoEnabled;
        videoTracks[0].enabled = _isVideoEnabled;
        if (AppConfig.isDev) debugPrint('[WebRTC] Video: $_isVideoEnabled');
      }
    }
  }

  /// Toggle speaker/earpiece
  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    await Helper.setSpeakerphoneOn(_isSpeakerOn);
    if (AppConfig.isDev) debugPrint('[WebRTC] Speaker: $_isSpeakerOn');
  }

  /// Switch between front and back camera
  Future<void> switchCamera() async {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        await Helper.switchCamera(videoTracks[0]);
        _isFrontCamera = !_isFrontCamera;
        if (AppConfig.isDev) debugPrint('[WebRTC] Camera switched: front=$_isFrontCamera');
      }
    }
  }

  /// Clean up all resources
  Future<void> dispose() async {
    try {
      // Stop local stream tracks
      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          await track.stop();
        }
        await _localStream!.dispose();
        _localStream = null;
      }

      // Dispose remote stream
      if (_remoteStream != null) {
        await _remoteStream!.dispose();
        _remoteStream = null;
      }

      // Close peer connection
      if (_peerConnection != null) {
        await _peerConnection!.close();
        _peerConnection = null;
      }

      // Reset state
      _isMuted = false;
      _isVideoEnabled = true;
      _isSpeakerOn = true;
      _isFrontCamera = true;
      _remoteDescriptionSet = false;

      // Stop quality monitoring
      stopQualityMonitoring();
      _connectionQuality = ConnectionQuality.excellent;
      _prevBytesReceived = 0;

      // Clear callbacks
      onIceCandidate = null;
      onRemoteStream = null;
      onConnectionStateChange = null;
      onIceConnectionStateChange = null;
      onConnectionQualityChange = null;

      if (AppConfig.isDev) debugPrint('[WebRTC] Disposed');
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[WebRTC] Dispose error: $e');
    }
  }

  /// Convert RTCSessionDescription to Map for socket transmission
  static Map<String, dynamic> sdpToMap(RTCSessionDescription sdp) {
    return {
      'type': sdp.type,
      'sdp': sdp.sdp,
    };
  }

  /// Create RTCSessionDescription from Map received via socket
  static RTCSessionDescription mapToSdp(Map<String, dynamic> map) {
    return RTCSessionDescription(
      map['sdp'] as String?,
      map['type'] as String?,
    );
  }

  /// Convert RTCIceCandidate to Map for socket transmission
  static Map<String, dynamic> candidateToMap(RTCIceCandidate candidate) {
    return {
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    };
  }

  /// Create RTCIceCandidate from Map received via socket
  static RTCIceCandidate mapToCandidate(Map<String, dynamic> map) {
    return RTCIceCandidate(
      map['candidate'] as String?,
      map['sdpMid'] as String?,
      map['sdpMLineIndex'] as int?,
    );
  }
}
