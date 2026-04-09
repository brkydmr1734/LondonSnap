import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Connection quality levels
enum ConnectionQuality { excellent, good, poor, disconnected }

/// WebRTC service for managing peer connections, media streams, and ICE candidates
class WebRTCService {
  /// Always-on logger for WebRTC events (works in production builds)
  void _log(String message) {
    debugPrint('[CALL-WebRTC] $message');
  }

  // ICE servers - STUN only as default; TURN credentials fetched from backend at runtime
  List<Map<String, dynamic>> _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  /// Whether TURN credentials have been set from backend
  bool _hasTurnCredentials = false;
  bool get hasTurnCredentials => _hasTurnCredentials;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // Callbacks for events
  Function(RTCIceCandidate)? onIceCandidate;
  Function(MediaStream)? onRemoteStream;
  Function(RTCPeerConnectionState)? onConnectionStateChange;
  Function(RTCIceConnectionState)? onIceConnectionStateChange;

  // NEW: Additional callbacks for connection state handling (2d)
  /// Called when ICE connection becomes unstable (disconnected state)
  Function()? onConnectionUnstable;

  /// Called when ICE connection has permanently failed
  Function()? onConnectionFailed;

  /// Called when peer connection reaches connected state
  Function()? onConnectionSuccess;

  // NEW: Callback for ICE restart timeout (2b)
  /// Called when ICE reconnection fails after timeout
  Function()? onIceReconnectionTimeout;

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

  // Track whether remote description has been set (for ICE candidate queuing) (2a)
  bool _hasRemoteDescription = false;
  bool get remoteDescriptionSet => _hasRemoteDescription;

  // ICE candidate queue for candidates received before remote description (2a)
  final List<RTCIceCandidate> _pendingCandidates = [];

  // Dispose guard (2c)
  bool _disposed = false;

  // ICE reconnection timeout timer (2b)
  Timer? _iceReconnectionTimer;
  static const Duration _iceReconnectionTimeout = Duration(seconds: 15);

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
    _hasTurnCredentials = servers.any((s) =>
        s['urls']?.toString().startsWith('turn') == true ||
        s['urls']?.toString().startsWith('turns') == true);
    // Redact credentials in logs
    final serverSummary = servers.map((s) => s['urls']).toList();
    _log('ICE servers updated: ${servers.length} servers, hasTURN=$_hasTurnCredentials, urls=$serverSummary');
  }

  /// Apply adaptive bitrate constraints based on connection quality
  Future<void> applyBandwidthConstraints(ConnectionQuality quality) async {
    if (_peerConnection == null) return;

    final senders = await _peerConnection!.getSenders();
    for (final sender in senders) {
      if (sender.track?.kind == 'video') {
        final params = sender.parameters;
        switch (quality) {
          case ConnectionQuality.excellent:
            // No cap — let WebRTC auto-manage
            params.encodings?.forEach((e) {
              e.maxBitrate = null;
              e.maxFramerate = null;
            });
            break;
          case ConnectionQuality.good:
            params.encodings?.forEach((e) {
              e.maxBitrate = 500000; // 500 kbps
              e.maxFramerate = 24;
            });
            break;
          case ConnectionQuality.poor:
            params.encodings?.forEach((e) {
              e.maxBitrate = 150000; // 150 kbps
              e.maxFramerate = 15;
            });
            break;
          case ConnectionQuality.disconnected:
            params.encodings?.forEach((e) {
              e.maxBitrate = 50000; // 50 kbps
              e.maxFramerate = 10;
            });
            break;
        }
        await sender.setParameters(params);
      }
    }
    _log('Applied bandwidth constraints for quality: $quality');
  }

  /// Initialize WebRTC peer connection
  Future<void> initialize({required bool isVideoCall}) async {
    // Dispose any existing connection first
    await dispose();

    // Reset disposed flag so this instance is usable again
    _disposed = false;

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

      _log('Creating peer connection (video=$isVideoCall, iceServers=${_iceServers.length}, hasTURN=$_hasTurnCredentials)');
      _peerConnection = await createPeerConnection(config, constraints);
      _log('Peer connection created successfully');

      // Get user media
      await _getUserMedia(isVideoCall);

      // Add local tracks to peer connection
      if (_localStream != null) {
        final tracks = _localStream!.getTracks();
        for (final track in tracks) {
          await _peerConnection!.addTrack(track, _localStream!);
          _log('Local track added: kind=${track.kind}, id=${track.id}');
        }
      }

      // Setup event listeners
      _setupPeerConnectionListeners();

      _log('Initialized (video=$isVideoCall, iceServers=${_iceServers.length}, hasTURN=$_hasTurnCredentials)');
    } catch (e, stack) {
      _log('Initialize ERROR: $e\n$stack');
      rethrow;
    }
  }

  /// Start local camera preview only (no peer connection).
  /// Used to show the user's own camera while the call is ringing.
  /// The stream will be reused when full WebRTC is initialized via [initialize].
  Future<void> startLocalPreview() async {
    if (_localStream != null) return; // already have a stream
    _disposed = false;
    try {
      final constraints = {
        'audio': false, // no audio needed for preview
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
      };
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      _isFrontCamera = true;
      _log('Local camera preview started (tracks=${_localStream?.getTracks().length})');
    } catch (e) {
      _log('startLocalPreview ERROR: $e');
    }
  }

  /// Stop local preview stream (if full init hasn't happened yet).
  Future<void> stopLocalPreview() async {
    if (_peerConnection != null) return; // full WebRTC active, don't stop
    await _disposeLocalStream();
    _log('Local preview stopped');
  }

  Future<void> _disposeLocalStream() async {
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }
  }

  /// Get user media (audio and optionally video)
  /// Falls back to audio-only if video capture fails (graceful degradation)
  Future<void> _getUserMedia(bool isVideoCall) async {
    try {
      // If we already have a preview stream (from startLocalPreview), 
      // stop it and get a fresh one with audio
      if (_localStream != null) {
        _log('Replacing preview-only stream with full audio+video stream');
        await _disposeLocalStream();
      }

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

      try {
        _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      } catch (videoError) {
        // Graceful degradation: if video fails, fall back to audio-only
        if (isVideoCall) {
          _log('WARNING: Video capture failed, falling back to audio-only: $videoError');
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': false,
          });
          _isVideoEnabled = false;
        } else {
          rethrow;
        }
      }

      // Set default speaker mode
      // Video calls: speaker ON (like Snapchat/FaceTime)
      // Audio calls: earpiece (speaker OFF)
      try {
        final defaultSpeaker = isVideoCall;
        await Helper.setSpeakerphoneOn(defaultSpeaker);
        _isSpeakerOn = defaultSpeaker;
        _log('Default speaker set: $_isSpeakerOn (video=$isVideoCall)');
      } catch (e) {
        _log('setSpeakerphoneOn failed during init: $e');
        _isSpeakerOn = isVideoCall; // assume default based on call type
      }

      _log('Got user media (audio=true, video=$isVideoCall, tracks=${_localStream?.getTracks().length ?? 0})');
    } catch (e, stack) {
      _log('getUserMedia ERROR: $e\n$stack');
      rethrow;
    }
  }

  /// Setup peer connection event listeners
  void _setupPeerConnectionListeners() {
    _peerConnection?.onIceCandidate = (candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        _log('ICE candidate: ${candidate.candidate!.substring(0, candidate.candidate!.length.clamp(0, 40))}...');
        onIceCandidate?.call(candidate);
      }
    };

    _peerConnection?.onIceConnectionState = (state) {
      _log('ICE connection state changed: $state');
      onIceConnectionStateChange?.call(state);
    };

    // Connection state handling (2d)
    _peerConnection?.onConnectionState = (state) {
      _log('Peer connection state changed: $state');
      onConnectionStateChange?.call(state);

      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _log('Connection established successfully');
          _cancelIceReconnectionTimer();
          onConnectionSuccess?.call();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _log('Connection unstable — peer disconnected');
          onConnectionUnstable?.call();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _log('Connection failed permanently');
          _cancelIceReconnectionTimer();
          onConnectionFailed?.call();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _log('Connection closed — running cleanup');
          _cancelIceReconnectionTimer();
          dispose();
          break;
        default:
          break;
      }
    };

    _peerConnection?.onTrack = (event) {
      _log('Remote track received: kind=${event.track.kind}, streams=${event.streams.length}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);
      }
    };

    _peerConnection?.onAddStream = (stream) {
      _log('Remote stream added (tracks=${stream.getTracks().length})');
      _remoteStream = stream;
      onRemoteStream?.call(stream);
    };

    _peerConnection?.onRemoveStream = (stream) {
      _log('Remote stream removed (tracks=${stream.getTracks().length})');
    };
  }

  /// Start monitoring connection quality via getStats()
  void startQualityMonitoring() {
    _statsTimer?.cancel();
    _prevBytesReceived = 0;
    _statsTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkConnectionQuality());
    _log('Quality monitoring started');
  }

  /// Stop monitoring
  void stopQualityMonitoring() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _log('Quality monitoring stopped');
  }

  Future<void> _checkConnectionQuality() async {
    if (_peerConnection == null || _disposed) return;

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
        _log('Quality changed: $newQuality (rtt=${roundTripTime?.toStringAsFixed(3)}, loss=${packetLossPercent?.toStringAsFixed(1)}%, bytes=$currentBytesReceived)');
      }
    } catch (e, stack) {
      _log('Stats collection error: $e\n$stack');
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
      _log('Created SDP offer');
      return offer;
    } catch (e, stack) {
      _log('createOffer ERROR: $e\n$stack');
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
      _log('Created SDP answer');
      return answer;
    } catch (e, stack) {
      _log('createAnswer ERROR: $e\n$stack');
      rethrow;
    }
  }

  /// Set remote description (SDP from other peer)
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    try {
      await _peerConnection!.setRemoteDescription(description);
      _hasRemoteDescription = true;
      _log('Remote description set: ${description.type}');

      // Drain pending ICE candidates queue (2a)
      await _drainPendingCandidates();
    } catch (e, stack) {
      _log('setRemoteDescription ERROR: $e\n$stack');
      rethrow;
    }
  }

  /// Drain all queued ICE candidates after remote description is set (2a)
  Future<void> _drainPendingCandidates() async {
    if (_pendingCandidates.isEmpty) return;

    final count = _pendingCandidates.length;
    _log('Draining $count pending ICE candidates');

    final candidates = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();

    int added = 0;
    int failed = 0;
    for (final candidate in candidates) {
      try {
        await _peerConnection!.addCandidate(candidate);
        added++;
      } catch (e, stack) {
        failed++;
        _log('Failed to add queued ICE candidate: $e\n$stack');
        // Continue — don't throw so one bad candidate doesn't break the rest
      }
    }

    _log('Queue drain complete: $added added, $failed failed out of $count total');
  }

  /// Add ICE candidate from remote peer (2a - race-condition safe)
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    if (!_hasRemoteDescription) {
      _pendingCandidates.add(candidate);
      _log('ICE candidate queued (queue size: ${_pendingCandidates.length}) — remote description not set yet');
      return;
    }

    try {
      await _peerConnection!.addCandidate(candidate);
      _log('ICE candidate added directly');
    } catch (e, stack) {
      _log('addIceCandidate ERROR: $e\n$stack');
    }
  }

  /// Restart ICE negotiation (2b) — called by CallProvider on network change
  /// Returns the new SDP offer so CallProvider can send it via signaling
  Future<RTCSessionDescription?> restartIce() async {
    if (_peerConnection == null || _disposed) {
      _log('restartIce: no peer connection or disposed, aborting');
      return null;
    }

    try {
      _log('Restarting ICE negotiation');

      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
        'iceRestart': true,
      });
      await _peerConnection!.setLocalDescription(offer);
      _log('ICE restart offer created');

      // Start reconnection timeout
      _startIceReconnectionTimer();

      return offer;
    } catch (e, stack) {
      _log('restartIce ERROR: $e\n$stack');
      return null;
    }
  }

  /// Start a timer that fires if ICE reconnection doesn't succeed within timeout (2b)
  void _startIceReconnectionTimer() {
    _cancelIceReconnectionTimer();
    _iceReconnectionTimer = Timer(_iceReconnectionTimeout, () {
      _log('ICE reconnection timed out after ${_iceReconnectionTimeout.inSeconds}s');
      onIceReconnectionTimeout?.call();
    });
    _log('ICE reconnection timer started (${_iceReconnectionTimeout.inSeconds}s)');
  }

  /// Cancel ICE reconnection timer
  void _cancelIceReconnectionTimer() {
    if (_iceReconnectionTimer != null) {
      _iceReconnectionTimer!.cancel();
      _iceReconnectionTimer = null;
    }
  }

  /// Toggle microphone mute
  void toggleMute() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        _isMuted = !_isMuted;
        audioTracks[0].enabled = !_isMuted;
        _log('Mute toggled: $_isMuted');
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
        _log('Video toggled: $_isVideoEnabled');
      }
    }
  }

  /// Toggle speaker/earpiece
  Future<void> toggleSpeaker() async {
    final newValue = !_isSpeakerOn;
    try {
      await Helper.setSpeakerphoneOn(newValue);
      _isSpeakerOn = newValue;
      _log('Speaker toggled: $_isSpeakerOn');
    } catch (e, stack) {
      _log('toggleSpeaker ERROR: $e\n$stack');
      // Don't update state if the call failed
    }
  }

  /// Switch between front and back camera
  Future<void> switchCamera() async {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        await Helper.switchCamera(videoTracks[0]);
        _isFrontCamera = !_isFrontCamera;
        _log('Camera switched: front=$_isFrontCamera');
      }
    }
  }

  /// Clean up all resources (2c - guaranteed, double-dispose safe)
  Future<void> dispose() async {
    if (_disposed) {
      _log('Dispose skipped — already disposed');
      return;
    }
    _disposed = true;
    _log('Dispose started');

    // Stop quality monitoring timer
    try {
      _statsTimer?.cancel();
      _statsTimer = null;
    } catch (e) {
      _log('Dispose: stats timer cleanup error: $e');
    }

    // Cancel ICE reconnection timer
    try {
      _cancelIceReconnectionTimer();
    } catch (e) {
      _log('Dispose: ICE reconnection timer cleanup error: $e');
    }

    // Stop and dispose local stream tracks
    try {
      if (_localStream != null) {
        final tracks = _localStream!.getTracks();
        _log('Dispose: stopping ${tracks.length} local tracks');
        for (final track in tracks) {
          try {
            await track.stop();
          } catch (e) {
            _log('Dispose: local track stop error: $e');
          }
        }
        await _localStream!.dispose();
        _localStream = null;
      }
    } catch (e) {
      _log('Dispose: local stream cleanup error: $e');
      _localStream = null;
    }

    // Dispose remote stream
    try {
      if (_remoteStream != null) {
        await _remoteStream!.dispose();
        _remoteStream = null;
      }
    } catch (e) {
      _log('Dispose: remote stream cleanup error: $e');
      _remoteStream = null;
    }

    // Close peer connection
    try {
      if (_peerConnection != null) {
        await _peerConnection!.close();
        _peerConnection = null;
      }
    } catch (e) {
      _log('Dispose: peer connection close error: $e');
      _peerConnection = null;
    }

    // Clear pending ICE candidates
    _pendingCandidates.clear();
    _hasRemoteDescription = false;

    // Reset all internal state so service can be reused
    _isMuted = false;
    _isVideoEnabled = true;
    _isSpeakerOn = true;
    _isFrontCamera = true;
    _connectionQuality = ConnectionQuality.excellent;
    _prevBytesReceived = 0;

    // Clear callbacks
    onIceCandidate = null;
    onRemoteStream = null;
    onConnectionStateChange = null;
    onIceConnectionStateChange = null;
    onConnectionQualityChange = null;
    onConnectionUnstable = null;
    onConnectionFailed = null;
    onConnectionSuccess = null;
    onIceReconnectionTimeout = null;

    _log('Dispose complete — all resources released');
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
