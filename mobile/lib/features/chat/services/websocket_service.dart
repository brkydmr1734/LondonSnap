import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/core/config/app_config.dart';
import 'package:londonsnaps/features/chat/models/chat_models.dart';

/// Events emitted by the chat polling service.
enum ChatEventType { newMessage, messagesRefreshed, error }

class ChatEvent {
  final ChatEventType type;
  final dynamic data;
  ChatEvent(this.type, [this.data]);
}

/// Replaces the old WebSocket-based service with HTTP polling.
/// Periodically checks for new messages on the active chat.
/// Used as fallback when Socket.IO is disconnected.
class ChatPollingService {
  static final ChatPollingService _instance = ChatPollingService._internal();
  factory ChatPollingService() => _instance;
  ChatPollingService._internal();

  final ApiService _api = ApiService();
  Timer? _pollTimer;
  String? _activeChatId;
  DateTime? _lastMessageTime;
  bool _isPolling = false;
  bool _isPaused = false;

  // Exponential backoff state
  int _consecutiveEmptyPolls = 0;
  static const Duration _minPollInterval = Duration(seconds: 2);
  static const Duration _maxPollInterval = Duration(seconds: 30);

  final _eventController = StreamController<ChatEvent>.broadcast();
  Stream<ChatEvent> get events => _eventController.stream;

  bool get isPolling => _pollTimer != null && !_isPaused;
  String? get activeChatId => _activeChatId;

  /// Calculate poll interval with exponential backoff
  Duration get _currentPollInterval {
    if (_consecutiveEmptyPolls == 0) return _minPollInterval;
    
    // Exponential backoff: 2s, 4s, 8s, 16s, max 30s
    final seconds = min(
      _minPollInterval.inSeconds * pow(2, _consecutiveEmptyPolls).toInt(),
      _maxPollInterval.inSeconds,
    );
    return Duration(seconds: seconds);
  }

  /// Start polling for a specific chat.
  void startPolling(String chatId, {DateTime? since}) {
    _activeChatId = chatId;
    _lastMessageTime = since ?? DateTime.now();
    _consecutiveEmptyPolls = 0;
    _isPaused = false;
    _schedulePoll();
  }

  /// Schedule the next poll with current backoff interval
  void _schedulePoll() {
    _pollTimer?.cancel();
    if (_activeChatId == null || _isPaused) return;
    
    _pollTimer = Timer(_currentPollInterval, () async {
      await _poll();
      _schedulePoll(); // Schedule next poll after this one completes
    });
  }

  /// Stop polling.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _activeChatId = null;
    _isPolling = false;
    _isPaused = false;
    _consecutiveEmptyPolls = 0;
  }

  /// Pause polling temporarily (e.g., when socket reconnects)
  void pausePolling() {
    _isPaused = true;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Resume polling if it was paused
  void resumePolling() {
    if (_activeChatId != null && _isPaused) {
      _isPaused = false;
      _schedulePoll();
    }
  }

  /// Reset backoff (call when new messages arrive or on activity)
  void resetBackoff() {
    _consecutiveEmptyPolls = 0;
  }

  Future<void> _poll() async {
    if (_isPolling || _activeChatId == null || _isPaused) return;
    _isPolling = true;
    
    try {
      final response = await _api.getChatMessages(
        _activeChatId!,
        limit: 20,
        after: _lastMessageTime?.toIso8601String(),
      );
      final data = response.data['data'];
      final messagesList = data['messages'] as List? ?? [];
      
      if (messagesList.isNotEmpty) {
        final newMessages = messagesList
            .map((m) => Message.fromJson(m as Map<String, dynamic>))
            .toList();
        
        // FIX: Use last message's createdAt (newest in batch) not first
        // Messages are returned in descending order (newest first)
        // so .last is actually the oldest, but since we're using 'after' param
        // we want the newest message time which is .first
        // Actually, we want the LATEST timestamp to avoid missing messages
        _lastMessageTime = newMessages
            .map((m) => m.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        
        _consecutiveEmptyPolls = 0; // Reset backoff on activity
        _eventController.add(ChatEvent(ChatEventType.newMessage, newMessages));
      } else {
        // No new messages, increase backoff
        _consecutiveEmptyPolls = min(_consecutiveEmptyPolls + 1, 5);
      }
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[POLL] Error: $e');
      // On error, don't increase backoff aggressively
    }
    
    _isPolling = false;
  }

  /// Mark a message as read via HTTP.
  Future<void> markAsRead(String chatId, String messageId) async {
    try {
      await _api.markAsRead(chatId, messageId);
    } catch (e) {
      if (AppConfig.isDev) debugPrint('[POLL] markAsRead error: $e');
    }
  }

  void dispose() {
    stopPolling();
    _eventController.close();
  }
}
