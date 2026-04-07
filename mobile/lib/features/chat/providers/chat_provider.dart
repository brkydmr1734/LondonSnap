import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/core/config/app_config.dart';
import 'package:londonsnaps/core/errors/app_exceptions.dart';
import 'package:londonsnaps/core/errors/error_handler.dart';
import 'package:londonsnaps/features/chat/models/chat_models.dart';
import 'package:londonsnaps/features/chat/services/websocket_service.dart';
import 'package:londonsnaps/features/chat/services/socket_service.dart';

/// Main chat state management provider.
/// Coordinates between Socket.IO (primary) and HTTP polling (fallback).
class ChatProvider extends ChangeNotifier {
  static final ChatProvider _instance = ChatProvider._internal();
  factory ChatProvider() => _instance;
  ChatProvider._internal();

  final ApiService _api = ApiService();
  final ChatPollingService _polling = ChatPollingService();
  final ChatSocketService _socket = ChatSocketService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // ===== State =====
  List<Chat> _chats = [];
  List<Message> _messages = [];
  bool _isLoading = false;
  String? _error;
  String? _activeChatId;
  bool _hasMoreMessages = true;
  
  // Message deduplication: track recent message IDs
  final Set<String> _recentMessageIds = {};
  static const int _maxRecentMessages = 100;
  
  // Pending/optimistic messages: tempId -> Message
  final Map<String, Message> _pendingMessages = {};

  // Subscriptions
  StreamSubscription? _pollSubscription;
  StreamSubscription? _socketSubscription;

  // ===== Getters =====
  List<Chat> get chats => List.unmodifiable(_chats);
  List<Message> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasMoreMessages => _hasMoreMessages;
  String? get activeChatId => _activeChatId;
  bool get isSocketConnected => _socket.isConnected;

  bool _initialized = false;

  /// Initialize provider and connect to WebSocket
  void init() {
    if (_initialized) return;
    _initialized = true;
    
    _pollSubscription = _polling.events.listen(_handlePollEvent);
    _socketSubscription = _socket.events.listen(_handleSocketEvent);
    _socket.addListener(_onSocketUpdate);
    
    // Set up delivery callback from socket service
    _socket.onMessageDelivered = _handleMessageDelivered;
    
    // Call system disabled - Coming Soon
    // CallProvider().init();
    
    // Connect WebSocket with stored token
    _connectWebSocket();
  }

  /// Connect WebSocket with auth token from storage
  Future<void> _connectWebSocket() async {
    try {
      final token = await _storage.read(key: 'access_token');
      if (token != null) {
        _socket.connect(token);
      }
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[CHAT] WebSocket connect error: $e');
    }
  }

  /// Reconnect WebSocket (call after login)
  Future<void> reconnectWebSocket() async {
    await _connectWebSocket();
  }

  /// Disconnect WebSocket (call on logout)
  void disconnectWebSocket() {
    _socket.disconnect();
    _polling.stopPolling();
  }

  /// Try to reconnect socket if disconnected
  Future<void> reconnectSocket() async {
    if (!_socket.isConnected) {
      await _connectWebSocket();
    }
  }

  void _onSocketUpdate() {
    // Socket state changed (connected/disconnected, typing users, online users)
    notifyListeners();
  }

  // =============================================
  // Socket Event Handling
  // =============================================

  void _handleSocketEvent(SocketEvent event) {
    switch (event.type) {
      case SocketEventType.connected:
        _onSocketConnected();
        break;

      case SocketEventType.disconnected:
        _onSocketDisconnected();
        break;

      case SocketEventType.newMessage:
        final message = event.data as Message;
        _handleNewMessage(message);
        break;

      case SocketEventType.messageDelivered:
        // Handled via callback, but also refresh UI if needed
        notifyListeners();
        break;

      case SocketEventType.messageRead:
        final receipt = event.data as ReadReceiptEvent;
        _handleMessageRead(receipt);
        break;

      case SocketEventType.messageDeleted:
        final data = event.data as Map<String, dynamic>;
        _handleMessageDeleted(data['messageId'], data['chatId']);
        break;

      case SocketEventType.messageExpired:
        final data = event.data as Map<String, dynamic>;
        _handleMessagesExpired(data['chatId'], data['messageIds'] as List<String>);
        break;

      case SocketEventType.typingStarted:
      case SocketEventType.typingStopped:
        // Typing state is managed by socket service, just notify UI
        notifyListeners();
        break;

      case SocketEventType.userOnline:
      case SocketEventType.userOffline:
        // Online state managed by socket service, update chat list UI
        notifyListeners();
        break;

      case SocketEventType.snapStatusUpdate:
        final snapEvent = event.data as SnapStatusUpdateEvent;
        _handleSnapStatusUpdate(snapEvent);
        break;

      case SocketEventType.error:
        if (AppConfig.isDev) debugPrint('[CHAT] Socket error: ${event.data}');
        break;

      // Call events are handled by CallProvider, ignore here
      case SocketEventType.callInitiated:
      case SocketEventType.callIncoming:
      case SocketEventType.callAccepted:
      case SocketEventType.callDeclined:
      case SocketEventType.callEnded:
      case SocketEventType.callMissed:
      case SocketEventType.callOffer:
      case SocketEventType.callAnswer:
      case SocketEventType.callIceCandidate:
        break;
    }
  }

  void _onSocketConnected() {
    if (AppConfig.isDev) debugPrint('[CHAT] WebSocket connected');
    
    // Stop polling - socket is now primary
    _polling.pausePolling();
    
    // Join active chat if any
    if (_activeChatId != null) {
      _socket.joinChat(_activeChatId!);
      
      // Fetch any missed messages since we were disconnected
      _fetchMissedMessages();
    }
  }

  void _onSocketDisconnected() {
    if (AppConfig.isDev) debugPrint('[CHAT] WebSocket disconnected, using polling');
    
    // Fall back to polling when disconnected
    if (_activeChatId != null && _messages.isNotEmpty) {
      _polling.startPolling(_activeChatId!, since: _messages.first.createdAt);
    }
  }

  /// Fetch any messages that might have been missed during disconnect
  Future<void> _fetchMissedMessages() async {
    if (_activeChatId == null || _messages.isEmpty) return;
    
    try {
      final response = await _api.getChatMessages(
        _activeChatId!,
        limit: 50,
        after: _messages.first.createdAt.toIso8601String(),
      );
      final data = response.data['data'];
      final messagesList = data['messages'] as List? ?? [];
      
      for (final msgData in messagesList) {
        final msg = Message.fromJson(msgData as Map<String, dynamic>);
        _handleNewMessage(msg, notify: false);
      }
      
      if (messagesList.isNotEmpty) {
        notifyListeners();
      }
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[CHAT] Fetch missed messages error: $e');
    }
  }

  // =============================================
  // New Message Handling (Main Bug Fix Area)
  // =============================================

  void _handleNewMessage(Message message, {bool notify = true}) {
    // Deduplication check
    if (_recentMessageIds.contains(message.id)) {
      if (AppConfig.isDev) debugPrint('[CHAT] Duplicate message ignored: ${message.id}');
      return;
    }
    _addRecentMessageId(message.id);
    
    // Check if this is an echo of our own pending message
    _pendingMessages.remove(message.id);

    final isCurrentChat = message.chatId == _activeChatId;

    if (isCurrentChat) {
      // Message for current chat → add to messages list
      if (!_messages.any((m) => m.id == message.id)) {
        _messages.insert(0, message);
        
        // Auto-mark as read since user is viewing this chat
        _markMessageAsReadIfNeeded(message);
        
        // Auto-mark as delivered if message is from another user
        _markMessageAsDeliveredIfNeeded(message);
      }
    }

    // Update chat list
    _updateChatWithNewMessage(message, isCurrentChat);

    if (notify) notifyListeners();
  }

  void _updateChatWithNewMessage(Message message, bool isCurrentChat) {
    final idx = _chats.indexWhere((c) => c.id == message.chatId);
    
    if (idx != -1) {
      // Update existing chat
      final chat = _chats[idx];
      _chats[idx] = Chat(
        id: chat.id,
        type: chat.type,
        name: chat.name,
        imageUrl: chat.imageUrl,
        participants: chat.participants,
        lastMessage: message,
        // Only increment unread if NOT current chat
        unreadCount: isCurrentChat ? 0 : chat.unreadCount + 1,
        isMuted: chat.isMuted,
        isPinned: chat.isPinned,
        isDisappearing: chat.isDisappearing,
        disappearAfter: chat.disappearAfter,
        createdAt: chat.createdAt,
        updatedAt: DateTime.now(),
      );
      _sortChats();
    } else {
      // NEW CHAT: Message arrived for a chat not in our list (e.g., new snap chat)
      // Create a minimal chat entry so the user sees the notification
      final senderParticipant = message.sender != null
          ? ChatParticipant(
              id: message.senderId,
              user: message.sender!,
              role: 'MEMBER',
              joinedAt: DateTime.now(),
            )
          : null;

      final newChat = Chat(
        id: message.chatId,
        type: ChatType.direct,
        name: null,
        imageUrl: null,
        participants: senderParticipant != null ? [senderParticipant] : [],
        lastMessage: message,
        unreadCount: isCurrentChat ? 0 : 1,
        isMuted: false,
        isPinned: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _chats.insert(0, newChat);

      // Trigger background refresh to get full chat details (don't await)
      loadChats();
    }
  }

  void _sortChats() {
    _chats.sort((a, b) {
      // Pinned chats first
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      // Then by updatedAt descending
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  void _markMessageAsReadIfNeeded(Message message) {
    if (message.status != MessageStatus.read && _socket.isConnected) {
      _socket.markRead(message.chatId, messageIds: [message.id]);
    }
  }

  /// Mark message as delivered when it arrives from another user
  Future<void> _markMessageAsDeliveredIfNeeded(Message message) async {
    // Only mark as delivered if the message is not from the current user
    // We check by seeing if there's a sender and the message status is 'sent'
    // The sender check will be done in the method below
    _markAsDelivered(message.chatId, [message.id]);
  }

  /// Call API to mark messages as delivered
  Future<void> _markAsDelivered(String chatId, List<String> messageIds) async {
    try {
      await _api.markMessagesDelivered(chatId, messageIds);
      if (AppConfig.isDev) {
        debugPrint('[CHAT] Marked messages as delivered: $messageIds');
      }
    } catch (e) {
      // Non-critical, don't propagate error
      if (AppConfig.isDev) {
        debugPrint('[CHAT] Failed to mark as delivered: $e');
      }
    }
  }

  // =============================================
  // Message Read Handling
  // =============================================

  void _handleMessageRead(ReadReceiptEvent receipt) {
    final idx = _messages.indexWhere((m) => m.id == receipt.messageId);
    if (idx != -1) {
      final msg = _messages[idx];
      // Add read receipt if not already there
      if (!msg.readBy.any((r) => r.userId == receipt.userId)) {
        _messages[idx] = msg.copyWithReadBy([
          ...msg.readBy,
          ReadReceipt(userId: receipt.userId, readAt: receipt.readAt),
        ]);
        notifyListeners();
      }
    }
  }

  /// Handle message delivered event from socket
  void _handleMessageDelivered(String chatId, List<String> messageIds, String? deliveredAt) {
    if (AppConfig.isDev) {
      debugPrint('[CHAT] Messages delivered: chatId=$chatId, ids=$messageIds');
    }
    
    bool updated = false;
    
    // Update messages in current chat
    if (chatId == _activeChatId) {
      for (int i = 0; i < _messages.length; i++) {
        if (messageIds.contains(_messages[i].id) && 
            _messages[i].status == MessageStatus.sent) {
          _messages[i] = _messages[i].copyWithStatus(MessageStatus.delivered);
          updated = true;
        }
      }
    }
    
    // Update last message in chat list if it's one of the delivered messages
    final chatIdx = _chats.indexWhere((c) => c.id == chatId);
    if (chatIdx != -1) {
      final chat = _chats[chatIdx];
      if (chat.lastMessage != null && 
          messageIds.contains(chat.lastMessage!.id) &&
          chat.lastMessage!.status == MessageStatus.sent) {
        _chats[chatIdx] = Chat(
          id: chat.id,
          type: chat.type,
          name: chat.name,
          imageUrl: chat.imageUrl,
          participants: chat.participants,
          lastMessage: chat.lastMessage!.copyWithStatus(MessageStatus.delivered),
          unreadCount: chat.unreadCount,
          isMuted: chat.isMuted,
          isPinned: chat.isPinned,
          isDisappearing: chat.isDisappearing,
          disappearAfter: chat.disappearAfter,
          createdAt: chat.createdAt,
          updatedAt: chat.updatedAt,
        );
        updated = true;
      }
    }
    
    if (updated) {
      notifyListeners();
    }
  }

  void _handleMessageDeleted(String messageId, String chatId) {
    if (chatId == _activeChatId) {
      _messages.removeWhere((m) => m.id == messageId);
      notifyListeners();
    }
  }

  void _handleMessagesExpired(String chatId, List<String> messageIds) {
    if (chatId == _activeChatId) {
      _messages.removeWhere((m) => messageIds.contains(m.id));
      notifyListeners();
    }
  }

  // =============================================
  // Snap Status Updates
  // =============================================

  void _handleSnapStatusUpdate(SnapStatusUpdateEvent event) {
    // Find message by ID (not by scanning content)
    final idx = _messages.indexWhere((m) => m.id == event.messageId);
    if (idx != -1) {
      final msg = _messages[idx];
      if (msg.isSnapMessage) {
        final snapData = msg.snapData;
        if (snapData != null) {
          final newStatus = SnapStatus.fromString(event.status);
          final updatedSnapData = snapData.copyWithStatus(newStatus);
          _messages[idx] = msg.copyWithContent(updatedSnapData.toJsonString());
          notifyListeners();
        }
      }
    }

    // Also update the last message in chat list if it's this message
    final chatIdx = _chats.indexWhere((c) => c.id == event.chatId);
    if (chatIdx != -1) {
      final chat = _chats[chatIdx];
      if (chat.lastMessage?.id == event.messageId && chat.lastMessage?.isSnapMessage == true) {
        final snapData = chat.lastMessage!.snapData;
        if (snapData != null) {
          final newStatus = SnapStatus.fromString(event.status);
          final updatedSnapData = snapData.copyWithStatus(newStatus);
          final updatedMessage = chat.lastMessage!.copyWithContent(updatedSnapData.toJsonString());
          _chats[chatIdx] = Chat(
            id: chat.id,
            type: chat.type,
            name: chat.name,
            imageUrl: chat.imageUrl,
            participants: chat.participants,
            lastMessage: updatedMessage,
            unreadCount: chat.unreadCount,
            isMuted: chat.isMuted,
            isPinned: chat.isPinned,
            isDisappearing: chat.isDisappearing,
            disappearAfter: chat.disappearAfter,
            createdAt: chat.createdAt,
            updatedAt: chat.updatedAt,
          );
          notifyListeners();
        }
      }
    }
  }

  // =============================================
  // Polling Event Handling
  // =============================================

  void _handlePollEvent(ChatEvent event) {
    switch (event.type) {
      case ChatEventType.newMessage:
        // Only use polling events if WebSocket is disconnected
        if (!_socket.isConnected) {
          final newMessages = event.data as List<Message>;
          for (final msg in newMessages) {
            _handleNewMessage(msg);
          }
        }
        break;
      default:
        break;
    }
  }

  // =============================================
  // Deduplication Helpers
  // =============================================

  void _addRecentMessageId(String messageId) {
    _recentMessageIds.add(messageId);
    if (_recentMessageIds.length > _maxRecentMessages) {
      _recentMessageIds.remove(_recentMessageIds.first);
    }
  }

  // =============================================
  // API Methods
  // =============================================

  Future<void> loadChats() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final response = await _api.getChats();
      if (AppConfig.isDev) debugPrint('[CHAT] Raw response: ${response.data}');
      final data = response.data;
      final chatsData = data is Map ? data['data'] : null;
      final chatsList = chatsData is Map ? chatsData['chats'] as List? ?? [] : [];
      _chats = chatsList.map((c) => Chat.fromJson(c as Map<String, dynamic>)).toList();
      _sortChats();
      if (AppConfig.isDev) debugPrint('[CHAT] Loaded ${_chats.length} chats');
    } catch (e) {
      final ex = e is AppException ? e : ErrorHandler.handle(e);
      _error = ex.message;
    }
    
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadMessages(String chatId, {bool loadMore = false}) async {
    if (!loadMore) {
      // Entering a new chat
      if (_activeChatId != null && _activeChatId != chatId) {
        _socket.leaveChat(_activeChatId!);
      }
      _activeChatId = chatId;
      _messages = [];
      _hasMoreMessages = true;
      
      // Join WebSocket room for this chat
      if (_socket.isConnected) {
        _socket.joinChat(chatId);
        _polling.pausePolling();
      }
    }
    
    if (!_hasMoreMessages) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      final beforeDate = loadMore && _messages.isNotEmpty
          ? _messages.last.createdAt.toIso8601String()
          : null;
      final response = await _api.getChatMessages(chatId, limit: 30, before: beforeDate);
      final data = response.data['data'];
      final messagesList = data['messages'] as List? ?? [];
      final newMessages = messagesList.map((m) => Message.fromJson(m as Map<String, dynamic>)).toList();
      
      // Add to messages with deduplication
      for (final msg in newMessages) {
        if (!_messages.any((m) => m.id == msg.id)) {
          _messages.add(msg);
          _addRecentMessageId(msg.id);
        }
      }
      
      // Sort messages so newest is at index 0 (for reverse ListView)
      _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      _hasMoreMessages = newMessages.length >= 30;

      // Start polling as fallback if socket not connected
      if (!_socket.isConnected) {
        final since = _messages.isNotEmpty ? _messages.first.createdAt : null;
        _polling.startPolling(chatId, since: since);
      } else {
        // Socket connected, ensure polling is stopped
        _polling.pausePolling();
      }

      // Mark messages as read
      markChatAsRead(chatId);
    } catch (e) {
      final ex = e is AppException ? e : ErrorHandler.handle(e);
      _error = ex.message;
    }
    
    _isLoading = false;
    notifyListeners();
  }

  // =============================================
  // Send Message (Optimistic UI)
  // =============================================

  Future<void> sendMessage({
    required String chatId,
    required String content,
    String type = 'TEXT',
    String? replyToId,
    String? mediaUrl,
    int? duration,
  }) async {
    // Generate temporary ID for optimistic UI
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    
    // Create optimistic message with 'sending' status
    final optimisticMessage = Message(
      id: tempId,
      chatId: chatId,
      senderId: '',
      sender: null,
      type: MessageType.fromString(type),
      content: content,
      mediaUrl: mediaUrl,
      duration: duration,
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
    );
    
    // Add to messages immediately (optimistic UI)
    _messages.insert(0, optimisticMessage);
    _pendingMessages[tempId] = optimisticMessage;
    notifyListeners();
    
    try {
      final response = await _api.sendMessage(
        chatId: chatId,
        content: content,
        type: type,
        replyToId: replyToId,
        mediaUrl: mediaUrl,
        duration: duration,
      );
      
      final msgData = response.data['data']['message'];
      if (msgData != null) {
        final msg = Message.fromJson(msgData as Map<String, dynamic>);
        
        // Replace optimistic message with real one
        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (idx != -1) {
          _messages[idx] = msg;
        }
        _pendingMessages.remove(tempId);
        _addRecentMessageId(msg.id);
        
        // Update chat list
        final chatIdx = _chats.indexWhere((c) => c.id == chatId);
        if (chatIdx != -1) {
          final chat = _chats[chatIdx];
          _chats[chatIdx] = Chat(
            id: chat.id,
            type: chat.type,
            name: chat.name,
            imageUrl: chat.imageUrl,
            participants: chat.participants,
            lastMessage: msg,
            unreadCount: 0,
            isMuted: chat.isMuted,
            isPinned: chat.isPinned,
            isDisappearing: chat.isDisappearing,
            disappearAfter: chat.disappearAfter,
            createdAt: chat.createdAt,
            updatedAt: DateTime.now(),
          );
          _sortChats();
        }
        notifyListeners();
      }
    } catch (e) {
      // Update message status to 'failed'
      final idx = _messages.indexWhere((m) => m.id == tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWithStatus(MessageStatus.failed);
      }
      _pendingMessages.remove(tempId);
      
      final ex = e is AppException ? e : ErrorHandler.handle(e);
      _error = ex.message;
      notifyListeners();
    }
  }

  /// Retry sending a failed message
  Future<void> retrySendMessage(String messageId) async {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    
    final failedMsg = _messages[idx];
    if (failedMsg.status != MessageStatus.failed) return;
    
    // Remove the failed message
    _messages.removeAt(idx);
    notifyListeners();
    
    // Resend
    await sendMessage(
      chatId: failedMsg.chatId,
      content: failedMsg.content,
      type: failedMsg.type.value,
      mediaUrl: failedMsg.mediaUrl,
    );
  }

  // =============================================
  // Mark as Read
  // =============================================

  /// Mark all messages in chat as read
  void markChatAsRead(String chatId) {
    // Get unread message IDs to mark as read
    final unreadIds = _messages
        .where((m) => m.chatId == chatId && m.status != MessageStatus.read)
        .map((m) => m.id)
        .where((id) => !id.startsWith('temp_')) // Exclude optimistic messages
        .toList();
    
    if (unreadIds.isEmpty) return;
    
    if (_socket.isConnected) {
      _socket.markRead(chatId, messageIds: unreadIds);
    } else {
      // HTTP fallback - mark first unread
      _polling.markAsRead(chatId, unreadIds.first);
    }
    
    // Optimistically update local unread count
    final chatIdx = _chats.indexWhere((c) => c.id == chatId);
    if (chatIdx != -1 && _chats[chatIdx].unreadCount > 0) {
      final chat = _chats[chatIdx];
      _chats[chatIdx] = Chat(
        id: chat.id,
        type: chat.type,
        name: chat.name,
        imageUrl: chat.imageUrl,
        participants: chat.participants,
        lastMessage: chat.lastMessage,
        unreadCount: 0,
        isMuted: chat.isMuted,
        isPinned: chat.isPinned,
        isDisappearing: chat.isDisappearing,
        disappearAfter: chat.disappearAfter,
        createdAt: chat.createdAt,
        updatedAt: chat.updatedAt,
      );
      notifyListeners();
    }
  }

  void markAsRead(String chatId, String messageId) {
    if (_socket.isConnected) {
      _socket.markRead(chatId, messageIds: [messageId]);
    } else {
      _polling.markAsRead(chatId, messageId);
    }
  }

  // =============================================
  // Typing Indicators (Debounced)
  // =============================================

  /// Notify that user is typing in a chat
  void startTyping(String chatId) {
    _socket.startTyping(chatId);
  }

  /// Notify that user stopped typing
  void stopTyping(String chatId) {
    _socket.stopTyping(chatId);
  }

  /// Reset typing timer (call on each keystroke)
  void onTyping(String chatId) {
    _socket.resetTypingTimer(chatId);
  }

  /// Get users currently typing in a chat
  List<TypingUser> getTypingUsers(String chatId) {
    return _socket.getTypingUsers(chatId);
  }

  /// Check if anyone is typing in a chat
  bool isAnyoneTyping(String chatId) {
    return _socket.isAnyoneTyping(chatId);
  }

  /// Get typing indicator text for a chat
  String? getTypingText(String chatId) {
    return _socket.getTypingText(chatId);
  }

  /// Check if a user is online
  bool isUserOnline(String userId) {
    return _socket.isUserOnline(userId);
  }

  // =============================================
  // Other Chat Operations
  // =============================================

  Future<void> reactToMessage({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    try {
      await _api.reactToMessage(chatId, messageId, emoji);
    } catch (_) {
      // Backend endpoint may not exist yet — silently ignore
    }
  }

  Future<Chat?> createChat({required List<String> memberIds, String? name}) async {
    try {
      final Response response;
      if (memberIds.length == 1 && name == null) {
        response = await _api.getOrCreateDirectChat(memberIds.first);
      } else {
        response = await _api.createChat(memberIds: memberIds, name: name);
      }
      final chat = Chat.fromJson(response.data['data']['chat']);
      _chats.removeWhere((c) => c.id == chat.id);
      _chats.insert(0, chat);
      notifyListeners();
      return chat;
    } catch (e) {
      final ex = e is AppException ? e : ErrorHandler.handle(e);
      _error = ex.message;
      notifyListeners();
      return null;
    }
  }

  Future<void> muteChat(String chatId) async {
    try {
      await _api.muteChat(chatId);
      final idx = _chats.indexWhere((c) => c.id == chatId);
      if (idx != -1) {
        final chat = _chats[idx];
        _chats[idx] = Chat(
          id: chat.id,
          type: chat.type,
          name: chat.name,
          imageUrl: chat.imageUrl,
          participants: chat.participants,
          lastMessage: chat.lastMessage,
          unreadCount: chat.unreadCount,
          isMuted: !chat.isMuted,
          isPinned: chat.isPinned,
          isDisappearing: chat.isDisappearing,
          disappearAfter: chat.disappearAfter,
          createdAt: chat.createdAt,
          updatedAt: chat.updatedAt,
        );
        notifyListeners();
      }
    } catch (e) {
      final ex = e is AppException ? e : ErrorHandler.handle(e);
      _error = ex.message;
    }
  }

  Future<void> leaveChat(String chatId) async {
    try {
      await _api.leaveChat(chatId);
      _socket.leaveChat(chatId);
      _chats.removeWhere((c) => c.id == chatId);
      notifyListeners();
    } catch (e) {
      final ex = e is AppException ? e : ErrorHandler.handle(e);
      _error = ex.message;
    }
  }

  Future<void> deleteChat(String chatId) async {
    try {
      await _api.deleteChat(chatId);
      _socket.leaveChat(chatId);
      _chats.removeWhere((c) => c.id == chatId);
      if (_activeChatId == chatId) {
        _activeChatId = null;
        _messages.clear();
      }
      notifyListeners();
    } catch (e) {
      final ex = e is AppException ? e : ErrorHandler.handle(e);
      _error = ex.message;
      notifyListeners();
    }
  }

  /// Update chat disappearing message settings
  Future<void> updateDisappearingMessages(String chatId, {bool? isDisappearing, int? disappearAfter}) async {
    try {
      await _api.updateChat(
        chatId,
        isDisappearing: isDisappearing,
        disappearAfter: disappearAfter,
        clearDisappearAfter: disappearAfter == null && isDisappearing == false,
      );
      final idx = _chats.indexWhere((c) => c.id == chatId);
      if (idx != -1) {
        _chats[idx] = _chats[idx].copyWithDisappearing(
          isDisappearing: isDisappearing,
          disappearAfter: disappearAfter,
          clearDisappearAfter: isDisappearing == false,
        );
        notifyListeners();
      }
    } catch (e) {
      final ex = e is AppException ? e : ErrorHandler.handle(e);
      _error = ex.message;
      notifyListeners();
    }
  }

  /// Call when leaving a chat screen to stop polling.
  void deactivateChat() {
    if (_activeChatId != null) {
      _socket.stopTyping(_activeChatId!);
      _socket.leaveChat(_activeChatId!);
    }
    _activeChatId = null;
    _polling.stopPolling();
  }

  /// Clear error state
  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollSubscription?.cancel();
    _socketSubscription?.cancel();
    _socket.removeListener(_onSocketUpdate);
    _polling.dispose();
    
    // Clear all state
    _chats.clear();
    _messages.clear();
    _recentMessageIds.clear();
    _pendingMessages.clear();
    _activeChatId = null;
    
    super.dispose();
  }
}

