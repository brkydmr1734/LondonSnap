import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO; // ignore: library_prefixes
import 'package:londonsnaps/core/config/app_config.dart';
import 'package:londonsnaps/features/chat/models/chat_models.dart';

/// Socket.IO event names - must match backend websocket.service.ts exactly
class SocketEvents {
  // Client -> Server
  static const String sendMessage = 'send_message';
  static const String markRead = 'mark_read';
  static const String typingStart = 'typing';
  static const String typingStop = 'stop_typing';
  static const String joinChat = 'join_chat';
  static const String leaveChat = 'leave_chat';

  // Server -> Client
  static const String message = 'message';
  static const String messageRead = 'message_read';
  static const String messageDelivered = 'message:delivered';
  static const String messageDeleted = 'message_deleted';
  static const String messageExpired = 'message_expired';
  static const String typing = 'typing';
  static const String stopTyping = 'stop_typing';
  static const String userOnline = 'user_online';
  static const String userOffline = 'user_offline';
  static const String error = 'error';
  static const String snapStatusUpdate = 'snap_status_update';
  static const String backgroundChanged = 'background_changed';

  // Call events - Client -> Server
  static const String callInitiate = 'call_initiate';
  static const String callAccept = 'call_accept';
  static const String callDecline = 'call_decline';
  static const String callEnd = 'call_end';
  static const String callOffer = 'call_offer';
  static const String callAnswer = 'call_answer';
  static const String callIceCandidate = 'call_ice_candidate';

  // Call events - Server -> Client
  static const String callInitiated = 'call_initiated';
  static const String callIncoming = 'call_incoming';
  static const String callAccepted = 'call_accepted';
  static const String callDeclined = 'call_declined';
  static const String callEnded = 'call_ended';
  static const String callMissed = 'call_missed';
}

/// Typing user info from socket event
class TypingUser {
  final String id;
  final String chatId;
  final String userId;
  final String displayName;
  final String? avatarUrl;

  TypingUser({
    required this.id,
    required this.chatId,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  factory TypingUser.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return TypingUser(
      id: json['id'] ?? '${json['userId']}-${json['chatId']}',
      chatId: json['chatId'] ?? '',
      userId: json['userId'] ?? '',
      displayName: user?['displayName'] ?? 'Someone',
      avatarUrl: user?['avatarUrl'],
    );
  }
}

/// Read receipt event data
class ReadReceiptEvent {
  final String messageId;
  final String chatId;
  final String userId;
  final DateTime readAt;

  ReadReceiptEvent({
    required this.messageId,
    required this.chatId,
    required this.userId,
    required this.readAt,
  });

  factory ReadReceiptEvent.fromJson(Map<String, dynamic> json) {
    return ReadReceiptEvent(
      messageId: json['messageId'] ?? '',
      chatId: json['chatId'] ?? '',
      userId: json['userId'] ?? '',
      readAt: json['readAt'] != null
          ? DateTime.parse(json['readAt'])
          : DateTime.now(),
    );
  }
}

/// Incoming call event data
class IncomingCallEvent {
  final String callId;
  final String callerId;
  final String callerName;
  final String? callerAvatar;
  final String callType;

  IncomingCallEvent({
    required this.callId,
    required this.callerId,
    required this.callerName,
    this.callerAvatar,
    required this.callType,
  });

  factory IncomingCallEvent.fromJson(Map<String, dynamic> json) {
    return IncomingCallEvent(
      callId: json['callId'] ?? '',
      callerId: json['callerId'] ?? '',
      callerName: json['callerName'] ?? 'Unknown',
      callerAvatar: json['callerAvatar'],
      callType: json['callType'] ?? 'voice',
    );
  }

  bool get isVideoCall => callType == 'video';
}

/// Call ended event data
class CallEndedEvent {
  final String callId;
  final int? duration;

  CallEndedEvent({required this.callId, this.duration});

  factory CallEndedEvent.fromJson(Map<String, dynamic> json) {
    return CallEndedEvent(
      callId: json['callId'] ?? '',
      duration: json['duration'],
    );
  }
}

/// SDP offer/answer event data
class CallSdpEvent {
  final String callId;
  final Map<String, dynamic> sdp;

  CallSdpEvent({required this.callId, required this.sdp});

  factory CallSdpEvent.fromJson(Map<String, dynamic> json) {
    return CallSdpEvent(
      callId: json['callId'] ?? '',
      sdp: json['sdp'] as Map<String, dynamic>? ?? {},
    );
  }
}

/// ICE candidate event data
class CallIceCandidateEvent {
  final String callId;
  final Map<String, dynamic> candidate;

  CallIceCandidateEvent({required this.callId, required this.candidate});

  factory CallIceCandidateEvent.fromJson(Map<String, dynamic> json) {
    return CallIceCandidateEvent(
      callId: json['callId'] ?? '',
      candidate: json['candidate'] as Map<String, dynamic>? ?? {},
    );
  }
}

/// Snap status update event data
class SnapStatusUpdateEvent {
  final String chatId;
  final String messageId;
  final String snapId;
  final String status;
  final DateTime updatedAt;

  SnapStatusUpdateEvent({
    required this.chatId,
    required this.messageId,
    required this.snapId,
    required this.status,
    required this.updatedAt,
  });

  factory SnapStatusUpdateEvent.fromJson(Map<String, dynamic> json) {
    return SnapStatusUpdateEvent(
      chatId: json['chatId'] ?? '',
      messageId: json['messageId'] ?? '',
      snapId: json['snapId'] ?? '',
      status: json['status'] ?? 'SENT',
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
    );
  }
}

/// Socket events for provider to listen to
enum SocketEventType {
  connected,
  disconnected,
  newMessage,
  messageRead,
  messageDelivered,
  messageDeleted,
  messageExpired,
  typingStarted,
  typingStopped,
  userOnline,
  userOffline,
  snapStatusUpdate,
  backgroundChanged,
  error,
  // Call events
  callInitiated,
  callIncoming,
  callAccepted,
  callDeclined,
  callEnded,
  callMissed,
  callOffer,
  callAnswer,
  callIceCandidate,
}

class SocketEvent {
  final SocketEventType type;
  final dynamic data;
  SocketEvent(this.type, [this.data]);
}

/// Real-time WebSocket service using Socket.IO
/// Manages connection, events, and typing/presence state
class ChatSocketService extends ChangeNotifier {
  static final ChatSocketService _instance = ChatSocketService._internal();
  factory ChatSocketService() => _instance;
  ChatSocketService._internal();

  IO.Socket? _socket;
  bool _isConnected = false;
  String? _currentToken;
  String? _activeChatId;

  // Callback for message delivery events
  Function(String chatId, List<String> messageIds, String? deliveredAt)? _onMessageDelivered;

  /// Set callback for when messages are marked as delivered
  set onMessageDelivered(Function(String chatId, List<String> messageIds, String? deliveredAt)? callback) {
    _onMessageDelivered = callback;
  }

  // Typing state: chatId -> Map<userId, TypingUser>
  final Map<String, Map<String, TypingUser>> _typingUsers = {};
  // Typing timeout timers: chatId -> Map<userId, Timer>
  final Map<String, Map<String, Timer>> _typingTimeoutTimers = {};

  // Online users: userId -> isOnline
  final Set<String> _onlineUsers = {};

  // Typing debounce timers per chat (for our own typing)
  final Map<String, Timer?> _typingTimers = {};
  final Map<String, bool> _isTyping = {};

  // Message deduplication: track last N message IDs
  final Set<String> _recentMessageIds = {};
  static const int _maxRecentMessages = 100;

  // Event stream for provider to listen to
  final _eventController = StreamController<SocketEvent>.broadcast();
  Stream<SocketEvent> get events => _eventController.stream;

  bool get isConnected => _isConnected;
  String? get activeChatId => _activeChatId;

  /// Get the WebSocket URL from base API URL
  String get _wsUrl {
    final apiUrl = AppConfig.baseUrl;
    // Remove /api/v1 path to get base domain
    final uri = Uri.parse(apiUrl);
    // Use the host with proper scheme for socket.io
    return '${uri.scheme}://${uri.host}${uri.port != 80 && uri.port != 443 ? ':${uri.port}' : ''}';
  }

  /// Connect to WebSocket server with auth token
  void connect(String token) {
    if (_socket != null && _isConnected && _currentToken == token) {
      return; // Already connected with same token
    }

    disconnect(); // Clean up any existing connection

    _currentToken = token;

    if (AppConfig.isDev) debugPrint('[SOCKET] Connecting to $_wsUrl');

    _socket = IO.io(
      _wsUrl,
      IO.OptionBuilder()
          .setTransports(['polling', 'websocket'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .build(),
    );

    _setupListeners();
  }

  void _setupListeners() {
    if (_socket == null) return;

    _socket!.onConnect((_) {
      _isConnected = true;
      if (AppConfig.isDev) debugPrint('[SOCKET] Connected');
      _eventController.add(SocketEvent(SocketEventType.connected));
      
      // Re-join active chat room if any
      if (_activeChatId != null) {
        joinChat(_activeChatId!);
      }
      notifyListeners();
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      if (AppConfig.isDev) debugPrint('[SOCKET] Disconnected');
      _eventController.add(SocketEvent(SocketEventType.disconnected));
      
      // Clear online users on disconnect
      _onlineUsers.clear();
      
      notifyListeners();
    });

    _socket!.onConnectError((error) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Connect error: $error');
      _eventController.add(SocketEvent(SocketEventType.error, error.toString()));
    });

    _socket!.onError((error) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Error: $error');
      _eventController.add(SocketEvent(SocketEventType.error, error.toString()));
    });

    // New message received
    _socket!.on(SocketEvents.message, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] New message: $data');
      try {
        final message = Message.fromJson(data as Map<String, dynamic>);
        
        // Deduplicate: skip if we've seen this message recently
        if (_recentMessageIds.contains(message.id)) {
          if (AppConfig.isDev) debugPrint('[SOCKET] Duplicate message ignored: ${message.id}');
          return;
        }
        
        // Track this message ID
        _addRecentMessageId(message.id);
        
        _eventController.add(SocketEvent(SocketEventType.newMessage, message));
      } catch (e) {
        if (AppConfig.isDev) debugPrint('[SOCKET] Error parsing message: $e');
      }
    });

    // Message read receipt
    _socket!.on(SocketEvents.messageRead, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Message read: $data');
      try {
        final receipt = ReadReceiptEvent.fromJson(data as Map<String, dynamic>);
        _eventController.add(SocketEvent(SocketEventType.messageRead, receipt));
      } catch (e) {
        if (AppConfig.isDev) debugPrint('[SOCKET] Error parsing read receipt: $e');
      }
    });

    // Message delivered receipt
    _socket!.on(SocketEvents.messageDelivered, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Message delivered: $data');
      try {
        final chatId = data['chatId'] as String?;
        final messageIds = (data['messageIds'] as List?)?.cast<String>() ?? [];
        final deliveredAt = data['deliveredAt'] as String?;
        
        if (chatId != null && messageIds.isNotEmpty) {
          _onMessageDelivered?.call(chatId, messageIds, deliveredAt);
          _eventController.add(SocketEvent(
            SocketEventType.messageDelivered,
            {'chatId': chatId, 'messageIds': messageIds, 'deliveredAt': deliveredAt},
          ));
        }
      } catch (e) {
        if (AppConfig.isDev) debugPrint('[SOCKET] Error parsing delivered receipt: $e');
      }
    });

    // Message deleted
    _socket!.on(SocketEvents.messageDeleted, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Message deleted: $data');
      final messageId = data['messageId'] as String?;
      final chatId = data['chatId'] as String?;
      if (messageId != null && chatId != null) {
        _eventController.add(SocketEvent(
          SocketEventType.messageDeleted,
          {'messageId': messageId, 'chatId': chatId},
        ));
      }
    });

    // Messages expired (disappearing messages)
    _socket!.on(SocketEvents.messageExpired, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Messages expired: $data');
      final chatId = data['chatId'] as String?;
      final messageIds = (data['messageIds'] as List?)?.cast<String>() ?? [];
      if (chatId != null && messageIds.isNotEmpty) {
        _eventController.add(SocketEvent(
          SocketEventType.messageExpired,
          {'chatId': chatId, 'messageIds': messageIds},
        ));
      }
    });

    // Background changed
    _socket!.on(SocketEvents.backgroundChanged, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Background changed: $data');
      final chatId = data['chatId'] as String?;
      final backgroundUrl = data['backgroundUrl'] as String?;
      if (chatId != null) {
        _eventController.add(SocketEvent(
          SocketEventType.backgroundChanged,
          {'chatId': chatId, 'backgroundUrl': backgroundUrl},
        ));
      }
    });

    // Typing started
    _socket!.on(SocketEvents.typing, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Typing: $data');
      try {
        final typingUser = TypingUser.fromJson(data as Map<String, dynamic>);
        _addTypingUser(typingUser);
        _eventController.add(SocketEvent(SocketEventType.typingStarted, typingUser));
      } catch (e) {
        if (AppConfig.isDev) debugPrint('[SOCKET] Error parsing typing: $e');
      }
    });

    // Typing stopped
    _socket!.on(SocketEvents.stopTyping, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Stop typing: $data');
      final chatId = data['chatId'] as String?;
      final userId = data['userId'] as String?;
      if (chatId != null && userId != null) {
        _removeTypingUser(chatId, userId);
        _eventController.add(SocketEvent(
          SocketEventType.typingStopped,
          {'chatId': chatId, 'userId': userId},
        ));
      }
    });

    // User online
    _socket!.on(SocketEvents.userOnline, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] User online: $data');
      final userId = data['userId'] as String?;
      if (userId != null) {
        _onlineUsers.add(userId);
        _eventController.add(SocketEvent(SocketEventType.userOnline, userId));
        notifyListeners();
      }
    });

    // User offline
    _socket!.on(SocketEvents.userOffline, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] User offline: $data');
      final userId = data['userId'] as String?;
      if (userId != null) {
        _onlineUsers.remove(userId);
        _eventController.add(SocketEvent(SocketEventType.userOffline, userId));
        notifyListeners();
      }
    });

    // Error from server
    _socket!.on(SocketEvents.error, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Server error: $data');
      final message = data['message'] as String? ?? 'Unknown error';
      _eventController.add(SocketEvent(SocketEventType.error, message));
    });

    // Snap status update
    _socket!.on(SocketEvents.snapStatusUpdate, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Snap status update: $data');
      try {
        final event = SnapStatusUpdateEvent.fromJson(data as Map<String, dynamic>);
        _eventController.add(SocketEvent(SocketEventType.snapStatusUpdate, event));
      } catch (e) {
        if (AppConfig.isDev) debugPrint('[SOCKET] Error parsing snap status update: $e');
      }
    });

    // Call event listeners
    _setupCallListeners();
  }

  void _setupCallListeners() {
    if (_socket == null) return;

    // Call initiated acknowledgment
    _socket!.on(SocketEvents.callInitiated, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Call initiated: $data');
      final callId = data['callId'] as String?;
      if (callId != null) {
        _eventController.add(SocketEvent(SocketEventType.callInitiated, callId));
      }
    });

    // Incoming call
    _socket!.on(SocketEvents.callIncoming, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Incoming call: $data');
      try {
        final event = IncomingCallEvent.fromJson(data as Map<String, dynamic>);
        _eventController.add(SocketEvent(SocketEventType.callIncoming, event));
      } catch (e) {
        if (AppConfig.isDev) debugPrint('[SOCKET] Error parsing incoming call: $e');
      }
    });

    // Call accepted
    _socket!.on(SocketEvents.callAccepted, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Call accepted: $data');
      final callId = data['callId'] as String?;
      if (callId != null) {
        _eventController.add(SocketEvent(SocketEventType.callAccepted, callId));
      }
    });

    // Call declined
    _socket!.on(SocketEvents.callDeclined, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Call declined: $data');
      final callId = data['callId'] as String?;
      if (callId != null) {
        _eventController.add(SocketEvent(SocketEventType.callDeclined, callId));
      }
    });

    // Call ended
    _socket!.on(SocketEvents.callEnded, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Call ended: $data');
      try {
        final event = CallEndedEvent.fromJson(data as Map<String, dynamic>);
        _eventController.add(SocketEvent(SocketEventType.callEnded, event));
      } catch (e) {
        if (AppConfig.isDev) debugPrint('[SOCKET] Error parsing call ended: $e');
      }
    });

    // Call missed
    _socket!.on(SocketEvents.callMissed, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Call missed: $data');
      final callId = data['callId'] as String?;
      if (callId != null) {
        _eventController.add(SocketEvent(SocketEventType.callMissed, callId));
      }
    });

    // WebRTC SDP offer
    _socket!.on(SocketEvents.callOffer, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Call offer: $data');
      try {
        final event = CallSdpEvent.fromJson(data as Map<String, dynamic>);
        _eventController.add(SocketEvent(SocketEventType.callOffer, event));
      } catch (e) {
        if (AppConfig.isDev) debugPrint('[SOCKET] Error parsing call offer: $e');
      }
    });

    // WebRTC SDP answer
    _socket!.on(SocketEvents.callAnswer, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] Call answer: $data');
      try {
        final event = CallSdpEvent.fromJson(data as Map<String, dynamic>);
        _eventController.add(SocketEvent(SocketEventType.callAnswer, event));
      } catch (e) {
        if (AppConfig.isDev) debugPrint('[SOCKET] Error parsing call answer: $e');
      }
    });

    // WebRTC ICE candidate
    _socket!.on(SocketEvents.callIceCandidate, (data) {
      if (AppConfig.isDev) debugPrint('[SOCKET] ICE candidate: $data');
      try {
        final event = CallIceCandidateEvent.fromJson(data as Map<String, dynamic>);
        _eventController.add(SocketEvent(SocketEventType.callIceCandidate, event));
      } catch (e) {
        if (AppConfig.isDev) debugPrint('[SOCKET] Error parsing ICE candidate: $e');
      }
    });
  }

  void _addTypingUser(TypingUser user) {
    _typingUsers.putIfAbsent(user.chatId, () => {});
    _typingUsers[user.chatId]![user.userId] = user;
    
    // Set up auto-clear timeout (5 seconds)
    _typingTimeoutTimers.putIfAbsent(user.chatId, () => {});
    _typingTimeoutTimers[user.chatId]![user.userId]?.cancel();
    _typingTimeoutTimers[user.chatId]![user.userId] = Timer(
      const Duration(seconds: 5),
      () => _removeTypingUser(user.chatId, user.userId),
    );
    
    notifyListeners();
  }

  void _removeTypingUser(String chatId, String userId) {
    _typingUsers[chatId]?.remove(userId);
    if (_typingUsers[chatId]?.isEmpty ?? false) {
      _typingUsers.remove(chatId);
    }
    
    // Cancel and remove timeout timer
    _typingTimeoutTimers[chatId]?[userId]?.cancel();
    _typingTimeoutTimers[chatId]?.remove(userId);
    if (_typingTimeoutTimers[chatId]?.isEmpty ?? false) {
      _typingTimeoutTimers.remove(chatId);
    }
    
    notifyListeners();
  }

  /// Add message ID to recent set for deduplication
  void _addRecentMessageId(String messageId) {
    _recentMessageIds.add(messageId);
    
    // Keep set bounded
    if (_recentMessageIds.length > _maxRecentMessages) {
      _recentMessageIds.remove(_recentMessageIds.first);
    }
  }

  /// Check if message was recently processed (for deduplication)
  bool hasRecentMessage(String messageId) {
    return _recentMessageIds.contains(messageId);
  }

  /// Track a message ID to prevent duplicate processing
  void trackMessageId(String messageId) {
    _addRecentMessageId(messageId);
  }

  /// Disconnect from WebSocket server
  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    _currentToken = null;
    _activeChatId = null;
    _typingUsers.clear();
    _onlineUsers.clear();
    _typingTimers.forEach((_, timer) => timer?.cancel());
    _typingTimers.clear();
    _isTyping.clear();
    _recentMessageIds.clear();
    // Cancel all typing timeout timers
    _typingTimeoutTimers.forEach((_, userTimers) {
      userTimers.forEach((_, timer) => timer.cancel());
    });
    _typingTimeoutTimers.clear();
    notifyListeners();
  }

  // ============================================
  // Emit methods - Client -> Server
  // ============================================

  /// Send a message via WebSocket
  void sendMessage({
    required String chatId,
    String? content,
    String? type,
    String? mediaUrl,
    String? replyToId,
  }) {
    if (!_isConnected) return;
    
    final data = <String, dynamic>{'chatId': chatId};
    if (content != null) data['content'] = content;
    if (type != null) data['type'] = type;
    if (mediaUrl != null) data['mediaUrl'] = mediaUrl;
    if (replyToId != null) data['replyToId'] = replyToId;
    
    _socket?.emit(SocketEvents.sendMessage, data);
  }

  /// Mark messages as read
  void markRead(String chatId, {List<String>? messageIds}) {
    if (!_isConnected) return;
    
    final data = <String, dynamic>{'chatId': chatId};
    if (messageIds != null && messageIds.isNotEmpty) {
      data['messageIds'] = messageIds;
    }
    
    _socket?.emit(SocketEvents.markRead, data);
  }

  /// Start typing indicator (debounced)
  void startTyping(String chatId) {
    // Only emit if not already typing in this chat
    if (_isTyping[chatId] == true) return;

    _isTyping[chatId] = true;
    _socket?.emit(SocketEvents.typingStart, {'chatId': chatId});

    // Auto-stop typing after 3 seconds of no activity
    _typingTimers[chatId]?.cancel();
    _typingTimers[chatId] = Timer(const Duration(seconds: 3), () {
      stopTyping(chatId);
    });
  }

  /// Reset typing timer (call on each keystroke)
  void resetTypingTimer(String chatId) {
    if (_isTyping[chatId] != true) {
      startTyping(chatId);
      return;
    }

    // Reset the auto-stop timer
    _typingTimers[chatId]?.cancel();
    _typingTimers[chatId] = Timer(const Duration(seconds: 3), () {
      stopTyping(chatId);
    });
  }

  /// Stop typing indicator
  void stopTyping(String chatId) {
    if (_isTyping[chatId] != true) return;

    _isTyping[chatId] = false;
    _typingTimers[chatId]?.cancel();
    _typingTimers.remove(chatId);
    _socket?.emit(SocketEvents.typingStop, {'chatId': chatId});
  }

  /// Join a chat room
  void joinChat(String chatId) {
    _activeChatId = chatId;
    if (!_isConnected) return;
    _socket?.emit(SocketEvents.joinChat, {'chatId': chatId});
  }

  /// Leave a chat room
  void leaveChat(String chatId) {
    stopTyping(chatId);
    
    // Clear typing state for this chat
    _clearChatTypingState(chatId);
    
    if (_activeChatId == chatId) {
      _activeChatId = null;
    }
    
    if (!_isConnected) return;
    _socket?.emit(SocketEvents.leaveChat, {'chatId': chatId});
  }

  /// Clear all typing state for a chat
  void _clearChatTypingState(String chatId) {
    _typingUsers.remove(chatId);
    _typingTimeoutTimers[chatId]?.forEach((_, timer) => timer.cancel());
    _typingTimeoutTimers.remove(chatId);
    _typingTimers[chatId]?.cancel();
    _typingTimers.remove(chatId);
    _isTyping.remove(chatId);
  }

  // ============================================
  // Call emit methods - Client -> Server
  // ============================================

  /// Initiate a call
  void initiateCall({required String targetUserId, required String callType}) {
    _socket?.emit(SocketEvents.callInitiate, {
      'targetUserId': targetUserId,
      'callType': callType,
    });
  }

  /// Accept an incoming call
  void acceptCall(String callId) {
    _socket?.emit(SocketEvents.callAccept, {'callId': callId});
  }

  /// Decline an incoming call
  void declineCall(String callId) {
    _socket?.emit(SocketEvents.callDecline, {'callId': callId});
  }

  /// End an active call
  void endCall(String callId) {
    _socket?.emit(SocketEvents.callEnd, {'callId': callId});
  }

  /// Send WebRTC SDP offer
  void sendCallOffer({required String callId, required Map<String, dynamic> sdp}) {
    _socket?.emit(SocketEvents.callOffer, {
      'callId': callId,
      'sdp': sdp,
    });
  }

  /// Send WebRTC SDP answer
  void sendCallAnswer({required String callId, required Map<String, dynamic> sdp}) {
    _socket?.emit(SocketEvents.callAnswer, {
      'callId': callId,
      'sdp': sdp,
    });
  }

  /// Send WebRTC ICE candidate
  void sendIceCandidate({required String callId, required Map<String, dynamic> candidate}) {
    _socket?.emit(SocketEvents.callIceCandidate, {
      'callId': callId,
      'candidate': candidate,
    });
  }

  // ============================================
  // Getters for UI
  // ============================================

  /// Get list of users typing in a specific chat
  List<TypingUser> getTypingUsers(String chatId) {
    return _typingUsers[chatId]?.values.toList() ?? [];
  }

  /// Check if any users are typing in a chat
  bool isAnyoneTyping(String chatId) {
    return _typingUsers[chatId]?.isNotEmpty ?? false;
  }

  /// Get typing text for a chat (e.g., "John is typing..." or "John, Jane are typing...")
  String? getTypingText(String chatId) {
    final users = getTypingUsers(chatId);
    if (users.isEmpty) return null;
    if (users.length == 1) {
      return '${users.first.displayName} is typing...';
    }
    final names = users.map((u) => u.displayName).take(2).join(', ');
    return '$names are typing...';
  }

  /// Check if a user is online
  bool isUserOnline(String userId) {
    return _onlineUsers.contains(userId);
  }

  /// Get all online user IDs
  Set<String> get onlineUsers => Set.unmodifiable(_onlineUsers);

  @override
  void dispose() {
    disconnect();
    _eventController.close();
    super.dispose();
  }
}
