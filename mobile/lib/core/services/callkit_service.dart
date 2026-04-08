import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:londonsnaps/core/config/app_config.dart';

/// Service to integrate native CallKit (iOS) / ConnectionService (Android)
/// for incoming and outgoing calls.
class CallKitService {
  static final CallKitService _instance = CallKitService._internal();
  factory CallKitService() => _instance;
  CallKitService._internal();

  // Callbacks
  VoidCallback? onAccept;
  VoidCallback? onDecline;
  VoidCallback? onEnd;

  String? _currentCallKitId;
  StreamSubscription? _eventSubscription;

  /// Initialize event listeners for CallKit actions
  void init() {
    _eventSubscription?.cancel();
    _eventSubscription = FlutterCallkitIncoming.onEvent.listen(_onCallKitEvent);
    if (AppConfig.isDev) debugPrint('[CallKit] Initialized');
  }

  void _onCallKitEvent(CallEvent? event) {
    if (event == null) return;
    if (AppConfig.isDev) debugPrint('[CallKit] Event: ${event.event}');

    switch (event.event) {
      case Event.actionCallAccept:
        onAccept?.call();
        break;
      case Event.actionCallDecline:
        onDecline?.call();
        break;
      case Event.actionCallEnded:
        onEnd?.call();
        break;
      case Event.actionCallTimeout:
        onDecline?.call();
        break;
      default:
        break;
    }
  }

  /// Show incoming call notification (native iOS CallKit UI)
  Future<void> showIncomingCall({
    required String callId,
    required String callerName,
    String? callerAvatar,
    bool isVideo = false,
  }) async {
    _currentCallKitId = callId;

    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      avatar: callerAvatar,
      handle: callerName,
      type: isVideo ? 1 : 0, // 0 = audio, 1 = video
      duration: 30000, // 30 seconds before auto-dismiss
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Missed call',
        callbackText: 'Call back',
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: null,
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        actionColor: '#4CAF50',
        incomingCallNotificationChannelName: 'Incoming Call',
        missedCallNotificationChannelName: 'Missed Call',
        isShowCallID: false,
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
    if (AppConfig.isDev) debugPrint('[CallKit] Showing incoming call from $callerName');
  }

  /// Report outgoing call to system (so it shows in native call log)
  Future<void> reportOutgoingCall({
    required String callId,
    required String calleeName,
    bool isVideo = false,
  }) async {
    _currentCallKitId = callId;

    final params = CallKitParams(
      id: callId,
      nameCaller: calleeName,
      handle: calleeName,
      type: isVideo ? 1 : 0,
    );

    await FlutterCallkitIncoming.startCall(params);
    if (AppConfig.isDev) debugPrint('[CallKit] Reported outgoing call to $calleeName');
  }

  /// End current call in native system
  Future<void> endCall() async {
    if (_currentCallKitId != null) {
      await FlutterCallkitIncoming.endCall(_currentCallKitId!);
      if (AppConfig.isDev) debugPrint('[CallKit] Ended call $_currentCallKitId');
      _currentCallKitId = null;
    }
  }

  /// End all active calls
  Future<void> endAllCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
    _currentCallKitId = null;
  }

  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }
}
