import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/core/services/callkit_service.dart';
import 'package:londonsnaps/core/services/connectivity_service.dart';
import 'package:londonsnaps/core/services/ringtone_service.dart';
import 'package:londonsnaps/features/calls/services/webrtc_service.dart';
import 'package:londonsnaps/features/chat/services/socket_service.dart';
import 'package:permission_handler/permission_handler.dart';

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

/// Valid call state transitions
const Map<CallState, Set<CallState>> _validTransitions = {
  CallState.idle: {CallState.ringingOutgoing, CallState.ringingIncoming, CallState.active},
  CallState.ringingOutgoing: {CallState.connecting, CallState.ended},
  CallState.ringingIncoming: {CallState.connecting, CallState.ended},
  CallState.connecting: {CallState.active, CallState.ended},
  CallState.active: {CallState.ended},
  CallState.ended: {CallState.idle},
};

/// Call provider - manages call state and bridges WebRTC with Socket.io
class CallProvider extends ChangeNotifier {
  static final CallProvider _instance = CallProvider._internal();
  factory CallProvider() => _instance;
  CallProvider._internal();

  final ChatSocketService _socketService = ChatSocketService();
  final WebRTCService _webrtcService = WebRTCService();
  final CallKitService _callKitService = CallKitService();
  final ConnectivityService _connectivityService = ConnectivityService();
  final RingtoneService _ringtoneService = RingtoneService();
  StreamSubscription? _socketSubscription;
  bool _initialized = false;

  // Sequential async event queue — prevents race conditions during signaling
  final List<Future<void> Function()> _eventQueue = [];
  bool _processingQueue = false;

  /// Always-on logger for call events (works in production builds)
  void _log(String message) {
    // ignore: avoid_print
    print('[CALL-Provider] $message');
  }

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
  Timer? _disconnectTimer;
  Timer? _connectionTimeoutTimer;
  Timer? _iceRestartTimeoutTimer;

  // TURN credential cache
  List<Map<String, dynamic>>? _cachedTurnServers;
  DateTime? _turnCacheTimestamp;
  static const Duration _turnCacheTtl = Duration(hours: 1);

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
  ConnectionQuality get connectionQuality => _webrtcService.connectionQuality;

  // ---------------------------------------------------------------------------
  // State machine
  // ---------------------------------------------------------------------------

  /// Transition to a new call state. Returns true if the transition was valid.
  /// Transition to [CallState.idle] is always allowed (cleanup).
  bool _transitionTo(CallState newState) {
    if (newState == _state) return true; // no-op

    // Transition to idle is always allowed (cleanup path)
    if (newState == CallState.idle) {
      _log('State: $_state -> $newState (cleanup)');
      _state = newState;
      notifyListeners();
      return true;
    }

    final allowed = _validTransitions[_state] ?? {};
    if (!allowed.contains(newState)) {
      _log('WARNING: Invalid state transition $_state -> $newState (ignored)');
      return false;
    }

    _log('State: $_state -> $newState');
    _state = newState;
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initialize call provider and listen to socket events
  void init() {
    if (_initialized) return;
    _initialized = true;

    _socketSubscription?.cancel();
    _socketSubscription = _socketService.events.listen(_handleSocketEvent);

    // Initialize CallKit and wire callbacks
    _callKitService.init();
    _callKitService.onAccept = () {
      _log('CallKit: user accepted call');
      acceptCall();
    };
    _callKitService.onDecline = () {
      _log('CallKit: user declined call');
      declineCall();
    };
    _callKitService.onEnd = () {
      _log('CallKit: user ended call');
      endCall();
    };

    // Listen for network changes to trigger ICE restart during active calls
    _connectivityService.addListener(_onConnectivityChanged);

    _log('Initialized (socket connected: ${_socketService.isConnected})');
  }

  // ---------------------------------------------------------------------------
  // Network change handling
  // ---------------------------------------------------------------------------

  /// Handle network connectivity changes — trigger ICE restart if in active call
  void _onConnectivityChanged() {
    if (_state == CallState.active && _connectivityService.isOnline) {
      _log('Network changed while in active call, restarting ICE');
      try {
        _webrtcService.peerConnection?.restartIce();
      } catch (e) {
        _log('ERROR during ICE restart on network change: $e');
      }

      // Set a 15-second timeout — if ICE doesn't reconnect, end gracefully
      _iceRestartTimeoutTimer?.cancel();
      _iceRestartTimeoutTimer = Timer(const Duration(seconds: 15), () {
        if (_state == CallState.active) {
          _log('ICE did not reconnect within 15s after network change, ending call');
          _errorMessage = 'Connection lost after network change';
          notifyListeners();
          endCall();
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Socket event routing
  // ---------------------------------------------------------------------------

  /// Enqueue an async call event handler so they execute SEQUENTIALLY.
  /// This prevents race conditions (e.g. call_offer arriving while
  /// _initializeWebRTC is still running inside _handleCallAccepted).
  void _enqueueCallEvent(Future<void> Function() handler) {
    _eventQueue.add(handler);
    _drainEventQueue();
  }

  Future<void> _drainEventQueue() async {
    if (_processingQueue) return;
    _processingQueue = true;
    while (_eventQueue.isNotEmpty) {
      final fn = _eventQueue.removeAt(0);
      try {
        await fn();
      } catch (e) {
        _log('ERROR in queued event handler: $e');
      }
    }
    _processingQueue = false;
  }

  /// Handle socket events related to calls — all async handlers are queued
  void _handleSocketEvent(SocketEvent event) {
    switch (event.type) {
      case SocketEventType.callInitiated:
        _handleCallInitiated(event.data as String);
        break;
      case SocketEventType.callIncoming:
        _handleIncomingCall(event.data as IncomingCallEvent);
        break;
      case SocketEventType.callAccepted:
        _enqueueCallEvent(() => _handleCallAccepted(event.data as String));
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
        _enqueueCallEvent(() => _handleCallOffer(event.data as CallSdpEvent));
        break;
      case SocketEventType.callAnswer:
        _enqueueCallEvent(() => _handleCallAnswer(event.data as CallSdpEvent));
        break;
      case SocketEventType.callIceCandidate:
        _enqueueCallEvent(() => _handleIceCandidate(event.data as CallIceCandidateEvent));
        break;
      case SocketEventType.callBusy:
        _handleCallBusy(event.data as String);
        break;
      case SocketEventType.callBlocked:
        _handleCallBlocked(event.data as String);
        break;
      case SocketEventType.callError:
        _handleCallError(event.data as CallErrorEvent);
        break;
      case SocketEventType.callStateSync:
        _enqueueCallEvent(() => _handleCallStateSync(event.data as CallStateSyncEvent));
        break;
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Outgoing call
  // ---------------------------------------------------------------------------

  /// Initiate an outgoing call
  Future<void> initiateCall({
    required String targetUserId,
    required String targetUserName,
    String? targetUserAvatar,
    required bool isVideo,
  }) async {
    if (_state != CallState.idle) {
      _log('Cannot initiate call: already in state $_state');
      return;
    }

    // 3d: Check permissions BEFORE emitting any socket events
    try {
      final micStatus = await Permission.microphone.request();
      _log('Microphone permission: $micStatus');
      if (!micStatus.isGranted) {
        _errorMessage = 'Camera/microphone permission required for calls';
        notifyListeners();
        _log('ERROR: Microphone permission denied, aborting call');
        return;
      }

      if (isVideo) {
        final camStatus = await Permission.camera.request();
        _log('Camera permission: $camStatus');
        if (!camStatus.isGranted) {
          _errorMessage = 'Camera/microphone permission required for calls';
          notifyListeners();
          _log('ERROR: Camera permission denied, aborting call');
          return;
        }
      }
    } catch (e) {
      _log('ERROR requesting permissions: $e');
      _errorMessage = 'Camera/microphone permission required for calls';
      notifyListeners();
      return;
    }

    if (!_transitionTo(CallState.ringingOutgoing)) return;

    _direction = CallDirection.outgoing;
    _isVideoCall = isVideo;
    _remoteParticipant = CallParticipant(
      id: targetUserId,
      name: targetUserName,
      avatarUrl: targetUserAvatar,
    );
    notifyListeners();

    // Start outgoing ringback tone
    _ringtoneService.playOutgoingRingback().catchError((e) {
      _log('WARNING: ringback tone failed: $e');
    });

    // Start local camera preview for video calls (so user sees themselves while ringing)
    if (isVideo) {
      _webrtcService.startLocalPreview().then((_) {
        notifyListeners(); // trigger UI rebuild to show local video
      }).catchError((e) {
        _log('WARNING: local preview failed: $e');
      });
    }

    // Initiate call via socket
    try {
      if (!_socketService.isConnected) {
        _log('WARNING: Socket not connected when emitting call_initiate!');
      }
      _socketService.initiateCall(
        targetUserId: targetUserId,
        callType: isVideo ? 'video' : 'voice',
      );
      _log('Initiating ${isVideo ? 'video' : 'voice'} call to $targetUserName (socket: ${_socketService.isConnected})');
    } catch (e) {
      _log('ERROR emitting call_initiate: $e');
      _errorMessage = 'Failed to initiate call. Please check your connection.';
      notifyListeners();
      await _resetCallState();
    }
  }

  // ---------------------------------------------------------------------------
  // Socket event handlers
  // ---------------------------------------------------------------------------

  /// Handle call initiated acknowledgment from server
  void _handleCallInitiated(String callId) {
    _callId = callId;
    _log('Call initiated by server: callId=$callId');

    // Report outgoing call to native system now that we have the callId
    if (_direction == CallDirection.outgoing && _remoteParticipant != null) {
      try {
        _callKitService.reportOutgoingCall(
          callId: callId,
          calleeName: _remoteParticipant!.name,
          isVideo: _isVideoCall,
        );
      } catch (e) {
        _log('ERROR reporting outgoing call to CallKit: $e');
      }
    }

    notifyListeners();
  }

  /// Handle incoming call
  void _handleIncomingCall(IncomingCallEvent event) {
    if (_state != CallState.idle) {
      // Already in a call, decline this one
      _log('Declining incoming call ${event.callId}: already in state $_state');
      _socketService.declineCall(event.callId);
      return;
    }

    if (!_transitionTo(CallState.ringingIncoming)) return;

    _direction = CallDirection.incoming;
    _callId = event.callId;
    _isVideoCall = event.isVideoCall;
    _remoteParticipant = CallParticipant(
      id: event.callerId,
      name: event.callerName,
      avatarUrl: event.callerAvatar,
    );

    // Show native CallKit UI
    try {
      _callKitService.showIncomingCall(
        callId: event.callId,
        callerName: event.callerName,
        callerAvatar: event.callerAvatar,
        isVideo: event.isVideoCall,
      );
    } catch (e) {
      _log('ERROR showing CallKit incoming call: $e');
    }

    _log('Incoming call from ${event.callerName} (callId=${event.callId}, type=${event.callType})');

    // Play incoming ringtone (in-app; CallKit plays its own natively)
    _ringtoneService.playIncomingRingtone().catchError((e) {
      _log('WARNING: incoming ringtone failed: $e');
    });

    notifyListeners();
  }

  /// Accept an incoming call
  Future<void> acceptCall() async {
    if (_state != CallState.ringingIncoming || _callId == null) {
      _log('Cannot accept call: state=$_state, callId=$_callId');
      return;
    }

    if (!_transitionTo(CallState.connecting)) return;

    // Stop incoming ringtone — user answered
    _ringtoneService.stop();

    // Start 30s connection timeout
    _startConnectionTimeout();

    try {
      // Initialize WebRTC
      await _initializeWebRTC();
      // Notify UI so local video renderer picks up the stream
      notifyListeners();

      // Accept call via socket
      _socketService.acceptCall(_callId!);
      _log('Call accepted, WebRTC initialized, sent accept to server (callId=$_callId)');
    } catch (e) {
      _log('ERROR accepting call: $e');
      _errorMessage = 'Failed to access microphone/camera. Check permissions.';
      notifyListeners();
      await _cleanupOnError();
    }
  }

  /// Decline an incoming call
  void declineCall() {
    _log('Declining call (callId=$_callId, state=$_state)');
    if (_callId != null) {
      try {
        _socketService.declineCall(_callId!);
      } catch (e) {
        _log('ERROR emitting call_decline: $e');
      }
    }
    _resetCallState();
  }

  /// Handle call accepted by remote
  Future<void> _handleCallAccepted(String callId) async {
    // If _callId hasn't been set yet (race with _handleCallInitiated), set it now
    if (_callId == null && _state == CallState.ringingOutgoing) {
      _log('WARNING: call_accepted arrived before call_initiated, setting callId=$callId');
      _callId = callId;
    }

    if (_callId != callId) {
      _log('WARNING: call_accepted for callId=$callId but current is $_callId, ignoring');
      return;
    }

    if (!_transitionTo(CallState.connecting)) {
      _log('Cannot transition to connecting for accepted call $callId');
      return;
    }

    // Stop ringback tone — call is being connected
    _ringtoneService.stop();

    // Start 30s connection timeout
    _startConnectionTimeout();

    try {
      // Initialize WebRTC
      await _initializeWebRTC();
      // Notify UI so local video renderer picks up the stream
      notifyListeners();

      // Create and send offer (as call initiator)
      final offer = await _webrtcService.createOffer();
      _socketService.sendCallOffer(
        callId: _callId!,
        sdp: WebRTCService.sdpToMap(offer),
      );
      _log('Sent SDP offer to server (callId=$_callId)');
    } catch (e) {
      _log('ERROR after call accepted: $e');
      _errorMessage = 'Failed to establish call connection';
      notifyListeners();
      await _cleanupOnError();
    }
  }

  /// Handle call declined by remote
  void _handleCallDeclined(String callId) {
    if (_callId != callId) return;
    _log('Call declined by remote (callId=$callId)');
    _resetCallState();
  }

  /// Handle call busy (target is already in another call)
  void _handleCallBusy(String callId) {
    if (_callId != callId) return;
    _log('Target is busy (callId=$callId)');
    _errorMessage = 'User is on another call';
    notifyListeners();
    _resetCallState();
  }

  /// Handle call blocked (block relationship exists)
  void _handleCallBlocked(String callId) {
    if (_callId != callId) return;
    _log('Call blocked (callId=$callId)');
    _errorMessage = 'Unable to reach this user';
    notifyListeners();
    _resetCallState();
  }

  /// Handle call_error from server
  void _handleCallError(CallErrorEvent event) {
    debugPrint('[CALL-Provider] Received call_error: callId=${event.callId}, error=${event.error}');

    // If callId matches current active call, clean up
    if (event.callId != null && event.callId == _callId) {
      _log('call_error matches active call, cleaning up');
      _errorMessage = 'Call failed: ${event.error}';
      notifyListeners();
      _resetCallState();
    } else {
      _log('call_error for non-active call (current=$_callId), ignoring');
    }
  }

  /// Handle call_state_sync from server (reconnection recovery)
  Future<void> _handleCallStateSync(CallStateSyncEvent event) async {
    debugPrint('[CALL-Provider] Received call_state_sync: callId=${event.callId}, type=${event.callType}, isInitiator=${event.isInitiator}');

    if (_state == CallState.idle) {
      // Restore call state from server
      _log('Restoring call state from server sync: callId=${event.callId}');
      _callId = event.callId;
      _isVideoCall = event.isVideoCall;
      _direction = event.isInitiator ? CallDirection.outgoing : CallDirection.incoming;
      _remoteParticipant = CallParticipant(
        id: event.otherUserId,
        name: event.otherUserId, // name not available in sync payload
      );

      // Re-establish WebRTC connection
      try {
        await _initializeWebRTC();
        notifyListeners();

        if (event.isInitiator) {
          // We were the caller — re-send an offer
          final offer = await _webrtcService.createOffer();
          _socketService.sendCallOffer(
            callId: event.callId,
            sdp: WebRTCService.sdpToMap(offer),
          );
          _log('Re-sent SDP offer after state sync');
        }

        _transitionTo(CallState.connecting);
        _startConnectionTimeout();
      } catch (e) {
        _log('ERROR re-establishing WebRTC after state sync: $e');
        _errorMessage = 'Failed to reconnect call';
        notifyListeners();
        await _resetCallState();
      }
    } else if (_callId == event.callId) {
      _log('call_state_sync for already-active call ${event.callId}, ignoring');
    } else {
      _log('WARNING: call_state_sync for different call ${event.callId} while in $_state with callId=$_callId, ignoring');
    }
  }

  /// Cancel an outgoing call during ringing phase
  void cancelCall() {
    if (_state != CallState.ringingOutgoing || _callId == null) return;
    try {
      _socketService.cancelCall(_callId!);
    } catch (e) {
      _log('ERROR emitting call_cancel: $e');
    }
    _log('Call cancelled by user (callId=$_callId)');
    _resetCallState();
  }

  /// Handle call ended
  void _handleCallEnded(CallEndedEvent event) {
    if (_callId != event.callId) return;
    _log('Call ended by remote, duration: ${event.duration}s (callId=${event.callId})');
    _resetCallState();
  }

  /// Handle call missed (timeout)
  void _handleCallMissed(String callId) {
    if (_callId != callId) return;
    _log('Call missed/timeout (callId=$callId)');
    _resetCallState();
  }

  // ---------------------------------------------------------------------------
  // WebRTC SDP / ICE handlers
  // ---------------------------------------------------------------------------

  /// Handle WebRTC offer from remote
  Future<void> _handleCallOffer(CallSdpEvent event) async {
    if (_callId != event.callId) return;
    _log('Received SDP offer (callId=${event.callId})');

    try {
      final sdp = WebRTCService.mapToSdp(event.sdp);
      await _webrtcService.setRemoteDescription(sdp);

      // Process any pending ICE candidates
      _log('Processing ${_pendingCandidates.length} pending ICE candidates after offer');
      for (final candidate in _pendingCandidates) {
        try {
          await _webrtcService.addIceCandidate(candidate);
        } catch (e) {
          _log('ERROR adding pending ICE candidate: $e');
        }
      }
      _pendingCandidates.clear();

      // Create and send answer
      final answer = await _webrtcService.createAnswer();
      _socketService.sendCallAnswer(
        callId: _callId!,
        sdp: WebRTCService.sdpToMap(answer),
      );
      _log('Sent SDP answer to server (callId=$_callId)');
    } catch (e) {
      _log('ERROR handling offer: $e');
      _errorMessage = 'Failed to process call offer';
      notifyListeners();
      await _cleanupOnError();
    }
  }

  /// Handle WebRTC answer from remote
  Future<void> _handleCallAnswer(CallSdpEvent event) async {
    if (_callId != event.callId) return;
    _log('Received SDP answer (callId=${event.callId})');

    try {
      final sdp = WebRTCService.mapToSdp(event.sdp);
      await _webrtcService.setRemoteDescription(sdp);

      // Process any pending ICE candidates
      _log('Processing ${_pendingCandidates.length} pending ICE candidates after answer');
      for (final candidate in _pendingCandidates) {
        try {
          await _webrtcService.addIceCandidate(candidate);
        } catch (e) {
          _log('ERROR adding pending ICE candidate: $e');
        }
      }
      _pendingCandidates.clear();

      _log('Processed SDP answer (callId=$_callId)');
    } catch (e) {
      _log('ERROR handling answer: $e');
      _errorMessage = 'Failed to process call answer';
      notifyListeners();
      await _cleanupOnError();
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
        _log('Queued ICE candidate (remote desc not set yet, queue=${_pendingCandidates.length})');
        return;
      }

      await _webrtcService.addIceCandidate(candidate);
    } catch (e) {
      _log('ERROR handling ICE candidate: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // WebRTC initialization with TURN hardening
  // ---------------------------------------------------------------------------

  /// Initialize WebRTC service
  Future<void> _initializeWebRTC() async {
    _errorMessage = null;
    _pendingCandidates.clear();

    _log('Initializing WebRTC (isVideo=$_isVideoCall)...');

    // Permissions for RECEIVER are checked here; for CALLER they were checked
    // before emitting call_initiate. Re-verify to be safe.
    try {
      final micStatus = await Permission.microphone.request();
      _log('Microphone permission: $micStatus');
      if (!micStatus.isGranted) {
        throw Exception('Microphone permission denied');
      }

      if (_isVideoCall) {
        final camStatus = await Permission.camera.request();
        _log('Camera permission: $camStatus');
        if (!camStatus.isGranted) {
          throw Exception('Camera permission denied');
        }
      }
    } catch (e) {
      _log('ERROR requesting permissions during WebRTC init: $e');
      rethrow;
    }

    // Fetch TURN credentials (with caching + retry)
    await _fetchTurnCredentials();

    try {
      await _webrtcService.initialize(isVideoCall: _isVideoCall);
      _log('WebRTC peer connection created');
    } catch (e) {
      _log('ERROR initializing WebRTC: $e');
      rethrow;
    }

    // Set up callbacks
    _webrtcService.onIceCandidate = (candidate) {
      if (_callId != null) {
        try {
          _socketService.sendIceCandidate(
            callId: _callId!,
            candidate: WebRTCService.candidateToMap(candidate),
          );
        } catch (e) {
          _log('ERROR sending ICE candidate: $e');
        }
      }
    };

    _webrtcService.onRemoteStream = (stream) {
      _log('Remote stream received (tracks=${stream.getTracks().length})');
      notifyListeners();
    };

    _webrtcService.onConnectionStateChange = (state) {
      _handleConnectionStateChange(state);
    };

    _webrtcService.onIceConnectionStateChange = (state) {
      _handleIceConnectionStateChange(state);
    };

    _webrtcService.onConnectionQualityChange = (quality) {
      // Apply adaptive bitrate for video calls based on connection quality
      if (_isVideoCall) {
        _webrtcService.applyBandwidthConstraints(quality);
      }
      notifyListeners();
    };
  }

  /// Fetch TURN credentials with retry and caching
  Future<void> _fetchTurnCredentials() async {
    // Check cache first
    if (_cachedTurnServers != null && _turnCacheTimestamp != null) {
      final age = DateTime.now().difference(_turnCacheTimestamp!);
      if (age < _turnCacheTtl) {
        _webrtcService.setIceServers(_cachedTurnServers!);
        _log('Using cached TURN credentials (age=${age.inMinutes}m, servers=${_cachedTurnServers!.length}, hasTURN=${_webrtcService.hasTurnCredentials})');
        return;
      }
      _log('TURN cache expired (age=${age.inMinutes}m), fetching fresh credentials');
    }

    // Attempt 1
    try {
      await _doFetchTurn();
      return;
    } catch (e) {
      _log('WARNING: TURN credential fetch attempt 1 failed: $e');
    }

    // Retry after 1 second
    await Future.delayed(const Duration(seconds: 1));
    try {
      await _doFetchTurn();
      return;
    } catch (e) {
      _log('WARNING: TURN fetch failed after 2 attempts, falling back to STUN-only. Calls may fail on mobile networks! Error: $e');
      // Don't block the call — proceed with STUN-only
    }
  }

  /// Actually fetch TURN credentials from backend
  Future<void> _doFetchTurn() async {
    final credResponse = await ApiService().getTurnCredentials();
    final iceServers = credResponse.data['data']['iceServers'] as List;
    final servers = iceServers
        .map<Map<String, dynamic>>((s) => Map<String, dynamic>.from(s))
        .toList();
    _webrtcService.setIceServers(servers);

    // Cache
    _cachedTurnServers = servers;
    _turnCacheTimestamp = DateTime.now();
    _log('Fetched TURN credentials: ${servers.length} ICE servers (hasTURN=${_webrtcService.hasTurnCredentials})');
  }

  // ---------------------------------------------------------------------------
  // Connection timeout
  // ---------------------------------------------------------------------------

  /// Start a 30-second timeout after call is accepted. If state doesn't reach
  /// [CallState.active] within 30s, end the call.
  void _startConnectionTimeout() {
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (_state == CallState.connecting) {
        _log('Connection timed out after 30s (callId=$_callId)');
        _errorMessage = 'Connection timed out';
        notifyListeners();
        endCall();
      }
    });
    _log('Connection timeout started (30s)');
  }

  // ---------------------------------------------------------------------------
  // WebRTC connection state handling
  // ---------------------------------------------------------------------------

  /// Handle WebRTC connection state changes
  void _handleConnectionStateChange(RTCPeerConnectionState state) async {
    _log('WebRTC connection state: $state (callState=$_state)');

    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _disconnectTimer?.cancel();
        _disconnectTimer = null;
        _connectionTimeoutTimer?.cancel();
        _connectionTimeoutTimer = null;
        _iceRestartTimeoutTimer?.cancel();
        _iceRestartTimeoutTimer = null;

        if (_transitionTo(CallState.active)) {
          _startCallTimer();
          _webrtcService.startQualityMonitoring();
          _log('CALL ACTIVE - media flowing (callId=$_callId)');
        }
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        // Attempt ICE restart before giving up
        if (_state == CallState.active || _state == CallState.connecting) {
          try {
            _log('Connection FAILED, attempting ICE restart...');
            await _webrtcService.peerConnection?.restartIce();
          } catch (e) {
            _log('ICE restart failed: $e, ending call');
            _errorMessage = 'Call connection failed';
            notifyListeners();
            await _resetCallState();
          }
        }
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        // Start a 15-second timer — if not reconnected, end call
        if (_state == CallState.active) {
          _log('WebRTC DISCONNECTED, starting 15s recovery timer...');
          _disconnectTimer?.cancel();
          _disconnectTimer = Timer(const Duration(seconds: 15), () {
            _log('Still disconnected after 15s, ending call');
            _errorMessage = 'Call disconnected';
            notifyListeners();
            endCall();
          });
          // Try ICE restart after 5s
          Timer(const Duration(seconds: 5), () {
            if (_state == CallState.active) {
              try {
                _webrtcService.peerConnection?.restartIce();
              } catch (e) {
                _log('ERROR during delayed ICE restart: $e');
              }
            }
          });
        }
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        if (_state == CallState.active || _state == CallState.connecting) {
          _log('Peer connection closed, resetting');
          _resetCallState();
        }
        break;
      default:
        break;
    }
  }

  /// Handle ICE connection state changes
  void _handleIceConnectionStateChange(RTCIceConnectionState state) {
    _log('ICE connection state: $state (callState=$_state)');

    if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
        state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
      _connectionTimeoutTimer?.cancel();
      _connectionTimeoutTimer = null;
      _iceRestartTimeoutTimer?.cancel();
      _iceRestartTimeoutTimer = null;

      if (_state == CallState.connecting) {
        if (_transitionTo(CallState.active)) {
          _startCallTimer();
          _log('CALL ACTIVE via ICE connected (callId=$_callId)');
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Call timer
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // End call (idempotent)
  // ---------------------------------------------------------------------------

  /// End the current call. Idempotent: safe to call multiple times.
  Future<void> endCall() async {
    // Idempotent: if already idle or ended, just return
    if (_state == CallState.idle || _state == CallState.ended) {
      _log('endCall() ignored: already in state $_state');
      return;
    }

    _log('Ending call (callId=$_callId, state=$_state)');

    if (_callId != null) {
      try {
        _socketService.endCall(_callId!);
        _log('Sent call_end to server (callId=$_callId)');
      } catch (e) {
        _log('ERROR emitting call_end: $e');
      }
    }

    try {
      await _callKitService.endCall();
    } catch (e) {
      _log('ERROR ending CallKit call: $e');
    }

    await _resetCallState();
  }

  // ---------------------------------------------------------------------------
  // Media controls
  // ---------------------------------------------------------------------------

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
    try {
      await _webrtcService.toggleSpeaker();
    } catch (e) {
      _log('ERROR toggling speaker: $e');
    }
    notifyListeners();
  }

  /// Switch camera (front/back)
  Future<void> switchCamera() async {
    await _webrtcService.switchCamera();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Error cleanup helper
  // ---------------------------------------------------------------------------

  /// Cleanup after an error during call setup
  Future<void> _cleanupOnError() async {
    _log('Cleaning up after error (callId=$_callId)');

    // Notify server if we have a callId
    if (_callId != null) {
      try {
        _socketService.endCall(_callId!);
        _log('Sent call_end to server during error cleanup (callId=$_callId)');
      } catch (e) {
        _log('ERROR emitting call_end during cleanup: $e');
      }
    }

    await _resetCallState();
  }

  // ---------------------------------------------------------------------------
  // State reset
  // ---------------------------------------------------------------------------

  /// Reset call state to idle
  Future<void> _resetCallState() async {
    _log('Resetting call state (callId=$_callId)');

    // Stop any ringtone/ringback immediately
    _ringtoneService.stop();

    _callTimer?.cancel();
    _callTimer = null;
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;
    _iceRestartTimeoutTimer?.cancel();
    _iceRestartTimeoutTimer = null;

    try {
      await _webrtcService.dispose();
    } catch (e) {
      _log('ERROR disposing WebRTC: $e');
    }

    try {
      await _callKitService.endCall();
    } catch (e) {
      _log('ERROR ending CallKit during reset: $e');
    }

    _pendingCandidates.clear();

    _transitionTo(CallState.ended);

    // Reset to idle on next frame (no artificial delay)
    Future.microtask(() {
      _callId = null;
      _direction = null;
      _isVideoCall = false;
      _remoteParticipant = null;
      _callStartTime = null;
      _callDuration = 0;
      _errorMessage = null;
      _transitionTo(CallState.idle);
    });
  }

  // ---------------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------------

  /// Format call duration as MM:SS
  String get formattedDuration {
    final minutes = (_callDuration ~/ 60).toString().padLeft(2, '0');
    final seconds = (_callDuration % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _callTimer?.cancel();
    _disconnectTimer?.cancel();
    _connectionTimeoutTimer?.cancel();
    _iceRestartTimeoutTimer?.cancel();
    _connectivityService.removeListener(_onConnectivityChanged);
    _webrtcService.dispose();
    _callKitService.dispose();
    super.dispose();
  }
}
