import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:londonsnaps/core/config/app_config.dart';
import 'package:londonsnaps/features/calls/services/webrtc_service.dart';
import 'package:londonsnaps/features/chat/services/socket_service.dart';

/// Call states
enum CallState {
  idle,
  ringingOutgoing, // Calling someone
  ringingIncoming, // Someone is calling us
  connecting,      // WebRTC negotiation in progress
  active,          // Call is active
  ended,           // Call has ended
}

/// Call direction
enum CallDirection {
  outgoing,
  incoming,
}

/// Call participant info
class CallParticipant {
  final String id;
  final String name;
  final String? avatarUrl;

  CallParticipant({
    required this.id,
    required this.name,
    this.avatarUrl,
  });
}

/// Call provider - manages call state and bridges WebRTC with Socket.io
class CallProvider extends ChangeNotifier {
  static final CallProvider _instance = CallProvider._internal();
  factory CallProvider() => _instance;
  CallProvider._internal();

  final ChatSocketService _socketService = ChatSocketService();
  final WebRTCService _webrtcService = WebRTCService();
  StreamSubscription? _socketSubscription;

  // Call state
  CallState _state = CallState.idle;
  String? _callId;
  CallDirection? _direction;
  bool _isVideoCall = false;
  CallParticipant? _remoteParticipant;
  DateTime? _callStartTime;
  Timer? _callTimer;
  int _callDuration = 0;
  String? _errorMessage;

  // Pending ICE candidates (received before remote description is set)
  final List<RTCIceCandidate> _pendingCandidates = [];

  // Getters
  CallState get state => _state;
  String? get callId => _callId;
  CallDirection? get direction => _direction;
  bool get isVideoCall => _isVideoCall;
  CallParticipant? get remoteParticipant => _remoteParticipant;
  int get callDuration => _callDuration;
  String? get errorMessage => _errorMessage;
  WebRTCService get webrtcService => _webrtcService;
  bool get isMuted => _webrtcService.isMuted;
  bool get isVideoEnabled => _webrtcService.isVideoEnabled;
  bool get isSpeakerOn => _webrtcService.isSpeakerOn;
  bool get isFrontCamera => _webrtcService.isFrontCamera;

  /// Initialize call provider and listen to socket events
  void init() {
    _socketSubscription?.cancel();
    _socketSubscription = _socketService.events.listen(_handleSocketEvent);
    if (AppConfig.isDev) debugPrint('[CallProvider] Initialized');
  }

  /// Handle socket events related to calls
  void _handleSocketEvent(SocketEvent event) {
    switch (event.type) {
      case SocketEventType.callInitiated:
        _handleCallInitiated(event.data as String);
        break;
      case SocketEventType.callIncoming:
        _handleIncomingCall(event.data as IncomingCallEvent);
        break;
      case SocketEventType.callAccepted:
        _handleCallAccepted(event.data as String);
        break;
      case SocketEventType.callDeclined:
        _handleCallDeclined(event.data as String);
        break;
      case SocketEventType.callEnded:
        _handleCallEnded(event.data as CallEndedEvent);
        break;
      case SocketEventType.callMissed:
        _handleCallMissed(event.data as String);
        break;
      case SocketEventType.callOffer:
        _handleCallOffer(event.data as CallSdpEvent);
        break;
      case SocketEventType.callAnswer:
        _handleCallAnswer(event.data as CallSdpEvent);
        break;
      case SocketEventType.callIceCandidate:
        _handleIceCandidate(event.data as CallIceCandidateEvent);
        break;
      default:
        break;
    }
  }

  /// Initiate an outgoing call
  Future<void> initiateCall({
    required String targetUserId,
    required String targetUserName,
    String? targetUserAvatar,
    required bool isVideo,
  }) async {
    if (_state != CallState.idle) {
      if (AppConfig.isDev) debugPrint('[CallProvider] Cannot initiate call: already in call');
      return;
    }

    _state = CallState.ringingOutgoing;
    _direction = CallDirection.outgoing;
    _isVideoCall = isVideo;
    _remoteParticipant = CallParticipant(
      id: targetUserId,
      name: targetUserName,
      avatarUrl: targetUserAvatar,
    );
    notifyListeners();

    // Initiate call via socket
    _socketService.initiateCall(
      targetUserId: targetUserId,
      callType: isVideo ? 'video' : 'voice',
    );

    if (AppConfig.isDev) debugPrint('[CallProvider] Initiating ${isVideo ? 'video' : 'voice'} call to $targetUserName');
  }

  /// Handle call initiated acknowledgment from server
  void _handleCallInitiated(String callId) {
    _callId = callId;
    if (AppConfig.isDev) debugPrint('[CallProvider] Call initiated: $callId');
    notifyListeners();
  }

  /// Handle incoming call
  void _handleIncomingCall(IncomingCallEvent event) {
    if (_state != CallState.idle) {
      // Already in a call, decline this one
      _socketService.declineCall(event.callId);
      return;
    }

    _state = CallState.ringingIncoming;
    _direction = CallDirection.incoming;
    _callId = event.callId;
    _isVideoCall = event.isVideoCall;
    _remoteParticipant = CallParticipant(
      id: event.callerId,
      name: event.callerName,
      avatarUrl: event.callerAvatar,
    );

    if (AppConfig.isDev) debugPrint('[CallProvider] Incoming call from ${event.callerName}');
    notifyListeners();
  }

  /// Accept an incoming call
  Future<void> acceptCall() async {
    if (_state != CallState.ringingIncoming || _callId == null) return;

    _state = CallState.connecting;
    notifyListeners();

    try {
      // Initialize WebRTC
      await _initializeWebRTC();

      // Accept call via socket
      _socketService.acceptCall(_callId!);

      if (AppConfig.isDev) debugPrint('[CallProvider] Call accepted');
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[CallProvider] Error accepting call: $e');
      _errorMessage = 'Failed to access microphone/camera. Check permissions.';
      notifyListeners();
      await endCall();
    }
  }

  /// Decline an incoming call
  void declineCall() {
    if (_callId != null) {
      _socketService.declineCall(_callId!);
    }
    _resetCallState();
  }

  /// Handle call accepted by remote
  Future<void> _handleCallAccepted(String callId) async {
    if (_callId != callId) return;

    _state = CallState.connecting;
    notifyListeners();

    try {
      // Initialize WebRTC
      await _initializeWebRTC();

      // Create and send offer (as call initiator)
      final offer = await _webrtcService.createOffer();
      _socketService.sendCallOffer(
        callId: _callId!,
        sdp: WebRTCService.sdpToMap(offer),
      );

      if (AppConfig.isDev) debugPrint('[CallProvider] Sent offer');
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[CallProvider] Error after call accepted: $e');
      _errorMessage = 'Failed to establish call connection';
      notifyListeners();
      await endCall();
    }
  }

  /// Handle call declined by remote
  void _handleCallDeclined(String callId) {
    if (_callId != callId) return;
    if (AppConfig.isDev) debugPrint('[CallProvider] Call declined');
    _resetCallState();
  }

  /// Handle call ended
  void _handleCallEnded(CallEndedEvent event) {
    if (_callId != event.callId) return;
    if (AppConfig.isDev) debugPrint('[CallProvider] Call ended, duration: ${event.duration}s');
    _resetCallState();
  }

  /// Handle call missed (timeout)
  void _handleCallMissed(String callId) {
    if (_callId != callId) return;
    if (AppConfig.isDev) debugPrint('[CallProvider] Call missed');
    _resetCallState();
  }

  /// Handle WebRTC offer from remote
  Future<void> _handleCallOffer(CallSdpEvent event) async {
    if (_callId != event.callId) return;

    try {
      final sdp = WebRTCService.mapToSdp(event.sdp);
      await _webrtcService.setRemoteDescription(sdp);

      // Process any pending ICE candidates
      for (final candidate in _pendingCandidates) {
        await _webrtcService.addIceCandidate(candidate);
      }
      _pendingCandidates.clear();

      // Create and send answer
      final answer = await _webrtcService.createAnswer();
      _socketService.sendCallAnswer(
        callId: _callId!,
        sdp: WebRTCService.sdpToMap(answer),
      );

      if (AppConfig.isDev) debugPrint('[CallProvider] Sent answer');
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[CallProvider] Error handling offer: $e');
    }
  }

  /// Handle WebRTC answer from remote
  Future<void> _handleCallAnswer(CallSdpEvent event) async {
    if (_callId != event.callId) return;

    try {
      final sdp = WebRTCService.mapToSdp(event.sdp);
      await _webrtcService.setRemoteDescription(sdp);

      // Process any pending ICE candidates
      for (final candidate in _pendingCandidates) {
        await _webrtcService.addIceCandidate(candidate);
      }
      _pendingCandidates.clear();

      if (AppConfig.isDev) debugPrint('[CallProvider] Processed answer');
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[CallProvider] Error handling answer: $e');
    }
  }

  /// Handle ICE candidate from remote
  Future<void> _handleIceCandidate(CallIceCandidateEvent event) async {
    if (_callId != event.callId) return;

    try {
      final candidate = WebRTCService.mapToCandidate(event.candidate);

      // If remote description is not set yet, queue the candidate
      if (!_webrtcService.remoteDescriptionSet) {
        _pendingCandidates.add(candidate);
        if (AppConfig.isDev) debugPrint('[CallProvider] Queued ICE candidate (remote desc not set)');
        return;
      }

      await _webrtcService.addIceCandidate(candidate);
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[CallProvider] Error handling ICE candidate: $e');
    }
  }

  /// Initialize WebRTC service
  Future<void> _initializeWebRTC() async {
    _errorMessage = null;
    await _webrtcService.initialize(isVideoCall: _isVideoCall);

    // Set up callbacks
    _webrtcService.onIceCandidate = (candidate) {
      if (_callId != null) {
        _socketService.sendIceCandidate(
          callId: _callId!,
          candidate: WebRTCService.candidateToMap(candidate),
        );
      }
    };

    _webrtcService.onRemoteStream = (stream) {
      if (AppConfig.isDev) debugPrint('[CallProvider] Remote stream received');
      notifyListeners();
    };

    _webrtcService.onConnectionStateChange = (state) {
      _handleConnectionStateChange(state);
    };

    _webrtcService.onIceConnectionStateChange = (state) {
      _handleIceConnectionStateChange(state);
    };
  }

  /// Handle WebRTC connection state changes
  void _handleConnectionStateChange(RTCPeerConnectionState state) async {
    if (AppConfig.isDev) debugPrint('[CallProvider] Connection state: $state');

    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _state = CallState.active;
        _startCallTimer();
        notifyListeners();
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        // Attempt ICE restart before giving up
        if (_state == CallState.active || _state == CallState.connecting) {
          try {
            if (AppConfig.isDev) debugPrint('[CallProvider] Connection failed, attempting ICE restart');
            await _webrtcService.peerConnection?.restartIce();
          } catch (e) {
            if (AppConfig.isDev) debugPrint('[CallProvider] ICE restart failed: $e');
            _resetCallState();
          }
        }
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        if (_state == CallState.active || _state == CallState.connecting) {
          _resetCallState();
        }
        break;
      default:
        break;
    }
  }

  /// Handle ICE connection state changes
  void _handleIceConnectionStateChange(RTCIceConnectionState state) {
    if (AppConfig.isDev) debugPrint('[CallProvider] ICE state: $state');

    if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
        state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
      if (_state == CallState.connecting) {
        _state = CallState.active;
        _startCallTimer();
        notifyListeners();
      }
    }
  }

  /// Start call duration timer
  void _startCallTimer() {
    _callStartTime = DateTime.now();
    _callDuration = 0;
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callDuration = DateTime.now().difference(_callStartTime!).inSeconds;
      notifyListeners();
    });
  }

  /// End the current call
  Future<void> endCall() async {
    if (_callId != null) {
      _socketService.endCall(_callId!);
    }
    _resetCallState();
  }

  /// Toggle microphone mute
  void toggleMute() {
    _webrtcService.toggleMute();
    notifyListeners();
  }

  /// Toggle video on/off
  void toggleVideo() {
    _webrtcService.toggleVideo();
    notifyListeners();
  }

  /// Toggle speaker/earpiece
  Future<void> toggleSpeaker() async {
    await _webrtcService.toggleSpeaker();
    notifyListeners();
  }

  /// Switch camera (front/back)
  Future<void> switchCamera() async {
    await _webrtcService.switchCamera();
    notifyListeners();
  }

  /// Reset call state to idle
  Future<void> _resetCallState() async {
    _callTimer?.cancel();
    _callTimer = null;
    await _webrtcService.dispose();
    _pendingCandidates.clear();

    _state = CallState.ended;
    notifyListeners();

    // Reset to idle on next frame (no artificial delay)
    Future.microtask(() {
      _state = CallState.idle;
      _callId = null;
      _direction = null;
      _isVideoCall = false;
      _remoteParticipant = null;
      _callStartTime = null;
      _callDuration = 0;
      _errorMessage = null;
      notifyListeners();
    });
  }

  /// Format call duration as MM:SS
  String get formattedDuration {
    final minutes = (_callDuration ~/ 60).toString().padLeft(2, '0');
    final seconds = (_callDuration % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _callTimer?.cancel();
    _webrtcService.dispose();
    super.dispose();
  }
}
