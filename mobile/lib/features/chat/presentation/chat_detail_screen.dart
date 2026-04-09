import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';
import 'package:londonsnaps/features/chat/models/chat_models.dart';
import 'package:londonsnaps/features/chat/providers/chat_provider.dart';
import 'package:londonsnaps/features/auth/providers/auth_provider.dart';
import 'package:londonsnaps/features/calls/providers/call_provider.dart';
import 'package:londonsnaps/features/memories/providers/memory_provider.dart';
import 'package:londonsnaps/features/memories/models/memory_models.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:intl/intl.dart';

/// Snapchat-style color palette
class _SnapColors {
  static const Color background = Color(0xFF000000);
  static const Color ownBubble = Color(0xFF0EADFF);
  static const Color otherBubble = Color(0xFF1C1C1E);
  static const Color textPrimary = Colors.white;
  static const Color textMuted = Color(0xFF8E8E93);
  static const Color online = Color(0xFF4CAF50);
  static const Color divider = Color(0xFF2C2C2E);
}

class ChatDetailScreen extends StatefulWidget {
  final String chatId;
  const ChatDetailScreen({super.key, required this.chatId});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final ChatProvider _chatProvider = ChatProvider();
  final AuthProvider _authProvider = AuthProvider();
  final CallProvider _callProvider = CallProvider();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  Message? _replyingTo;

  // ── Voice recording state ──
  AudioRecorder? _audioRecorder;
  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordTimer;
  String? _recordingPath;
  bool _isSendingVoice = false;

  @override
  void initState() {
    super.initState();
    _chatProvider.addListener(_onUpdate);
    _authProvider.addListener(_onUpdate);
    _chatProvider.init();
    _chatProvider.loadMessages(widget.chatId);
    _scrollController.addListener(_onScroll);
    _messageController.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (_chatProvider.hasMoreMessages && !_chatProvider.isLoading) {
        _chatProvider.loadMessages(widget.chatId, loadMore: true);
      }
    }
  }

  void _onTextChanged() {
    if (_messageController.text.isNotEmpty) {
      _chatProvider.onTyping(widget.chatId);
    }
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus && _messageController.text.isNotEmpty) {
      _chatProvider.stopTyping(widget.chatId);
    }
  }

  @override
  void dispose() {
    _chatProvider.stopTyping(widget.chatId);
    _chatProvider.deactivateChat();
    _chatProvider.removeListener(_onUpdate);
    _authProvider.removeListener(_onUpdate);
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _recordTimer?.cancel();
    _audioRecorder?.dispose();
    super.dispose();
  }

  Chat? get _currentChat {
    try {
      return _chatProvider.chats.firstWhere((c) => c.id == widget.chatId);
    } catch (_) {
      return null;
    }
  }

  void _sendMessage() {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    _chatProvider.stopTyping(widget.chatId);
    _chatProvider.sendMessage(
      chatId: widget.chatId,
      content: content,
      replyToId: _replyingTo?.id,
    );
    _messageController.clear();
    setState(() => _replyingTo = null);
  }

  Future<void> _pickAndSendMedia(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 80);
    if (file == null) return;
    try {
      final api = ApiService();
      final response = await api.uploadMedia(file.path);
      final url = response.data['data']['media']['url'] as String;
      _chatProvider.sendMessage(
        chatId: widget.chatId,
        content: '',
        type: 'IMAGE',
        mediaUrl: url,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send media: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  // ── Voice recording ──

  Future<void> _startRecording() async {
    // Check microphone permission
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required')),
        );
      }
      return;
    }

    try {
      _audioRecorder?.dispose();
      _audioRecorder = AudioRecorder();

      final tempDir = await getTemporaryDirectory();
      _recordingPath =
          '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder!.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _recordingPath!,
      );

      _recordingSeconds = 0;
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordingSeconds++);
      });

      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('[VOICE] start error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start recording')),
        );
      }
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording || _isSendingVoice) return;
    setState(() => _isSendingVoice = true);

    _recordTimer?.cancel();
    final duration = _recordingSeconds;

    try {
      final path = await _audioRecorder?.stop();
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
      });

      if (path == null || path.isEmpty || duration < 1) {
        // Too short, discard
        if (path != null) File(path).deleteSync();
        return;
      }

      // Upload
      final api = ApiService();
      final response = await api.uploadMedia(path);
      final url = response.data['data']['media']['url'] as String;

      // Send
      _chatProvider.sendMessage(
        chatId: widget.chatId,
        content: '',
        type: 'AUDIO',
        mediaUrl: url,
        duration: duration,
      );

      // Clean temp file
      try {
        File(path).deleteSync();
      } catch (_) {}
    } catch (e) {
      debugPrint('[VOICE] send error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send voice message: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingVoice = false);
    }
  }

  void _cancelRecording() async {
    _recordTimer?.cancel();
    try {
      await _audioRecorder?.stop();
    } catch (_) {}
    if (_recordingPath != null) {
      try {
        File(_recordingPath!).deleteSync();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
        _recordingPath = null;
      });
    }
  }

  String _formatDuration(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _initiateCall({required bool isVideo}) async {
    final chat = _currentChat;
    final userId = _authProvider.currentUser?.id ?? '';
    final otherParticipants = chat?.participants
            .where((p) => p.user.id != userId)
            .toList() ??
        [];

    if (otherParticipants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No participant to call')),
      );
      return;
    }

    final participant = otherParticipants.first;

    if (_callProvider.state != CallState.idle) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already in a call')),
      );
      return;
    }

    // Ensure socket is connected before starting call
    if (!_chatProvider.isSocketConnected) {
      // ignore: avoid_print
      print('[Call] Socket not connected, attempting force reconnect...');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connecting to server...')),
      );

      // Use force reconnect with built-in retry logic
      final connected = await _chatProvider.forceReconnectSocket();

      if (!mounted) return;
      if (!connected) {
        // ignore: avoid_print
        print('[Call] Socket connection FAILED after all retries');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not connect to server. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      // ignore: avoid_print
      print('[Call] Socket reconnected successfully');
    }

    // ignore: avoid_print
    print('[Call] Initiating ${isVideo ? 'video' : 'voice'} call to ${participant.user.displayName}');

    _callProvider.initiateCall(
      targetUserId: participant.user.id,
      targetUserName: participant.user.displayName,
      targetUserAvatar: participant.user.avatarUrl,
      isVideo: isVideo,
    );

    context.push('/active-call');
  }

  @override
  Widget build(BuildContext context) {
    final chat = _currentChat;
    final userId = _authProvider.currentUser?.id ?? '';
    final otherParticipants =
        chat?.participants.where((p) => p.user.id != userId).toList() ?? [];
    final isOnline = otherParticipants.isNotEmpty &&
        (_chatProvider.isUserOnline(otherParticipants.first.user.id) ||
            otherParticipants.first.user.isOnline);
    final typingText = _chatProvider.getTypingText(widget.chatId);

    return Scaffold(
      backgroundColor: _SnapColors.background,
      appBar: _buildAppBar(chat, otherParticipants, isOnline, typingText, userId),
      body: Stack(
        children: [
          if (chat?.backgroundUrl != null)
            Positioned.fill(
              child: Image.network(
                chat!.backgroundUrl!,
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.3),
                colorBlendMode: BlendMode.darken,
                gaplessPlayback: true,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Column(
            children: [
              if (chat?.isDisappearing == true) _buildDisappearingBanner(),
              Expanded(child: _buildMessageList(userId, typingText)),
              if (_replyingTo != null) _buildReplyPreview(),
              _buildInputArea(),
            ],
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    Chat? chat,
    List<ChatParticipant> otherParticipants,
    bool isOnline,
    String? typingText,
    String userId,
  ) {
    return AppBar(
      backgroundColor: _SnapColors.background,
      elevation: 0,
      toolbarHeight: 56,
      leadingWidth: 40,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: _SnapColors.textPrimary, size: 20),
        onPressed: () => Navigator.pop(context),
        padding: EdgeInsets.zero,
      ),
      titleSpacing: 0,
      title: InkWell(
        onTap: () {
          if (otherParticipants.isNotEmpty) {
            context.push('/profile/${otherParticipants.first.user.id}');
          }
        },
        child: Row(
          children: [
            Stack(
              children: [
                if (otherParticipants.isNotEmpty && 
                    otherParticipants.first.user.avatarUrl != null && 
                    otherParticipants.first.user.avatarUrl!.isNotEmpty)
                  AvatarWidget(
                    avatarUrl: otherParticipants.first.user.avatarUrl,
                    radius: 16,
                  )
                else
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: _SnapColors.ownBubble,
                    child: Text(
                      otherParticipants.isNotEmpty
                          ? otherParticipants.first.user.displayName
                              .split(' ')
                              .map((w) => w.isNotEmpty ? w[0] : '')
                              .take(2)
                              .join()
                              .toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _SnapColors.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: _SnapColors.background, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    chat?.displayName(userId) ?? 'Chat',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _SnapColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (typingText != null)
                    Text(
                      typingText,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _SnapColors.ownBubble,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else if (isOnline)
                    const Text(
                      'Online',
                      style: TextStyle(fontSize: 11, color: _SnapColors.online),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.phone_outlined, 
            color: _SnapColors.textPrimary, size: 22),
          tooltip: 'Voice Call',
          onPressed: () => _initiateCall(isVideo: false),
        ),
        IconButton(
          icon: Icon(Icons.videocam_outlined, 
            color: _SnapColors.textPrimary, size: 22),
          tooltip: 'Video Call',
          onPressed: () => _initiateCall(isVideo: true),
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.menu, color: _SnapColors.textPrimary.withValues(alpha: 0.7), size: 22),
          color: _SnapColors.otherBubble,
          onSelected: (value) {
            switch (value) {
              case 'mute':
                _chatProvider.muteChat(widget.chatId);
                break;
              case 'disappearing':
                _showDisappearingMessagesSheet();
                break;
              case 'leave':
                _chatProvider.leaveChat(widget.chatId);
                Navigator.pop(context);
                break;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'mute',
              child: Row(
                children: [
                  Icon(
                    chat?.isMuted == true ? Icons.notifications : Icons.notifications_off,
                    size: 20,
                    color: _SnapColors.textPrimary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    chat?.isMuted == true ? 'Unmute' : 'Mute',
                    style: const TextStyle(color: _SnapColors.textPrimary),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'disappearing',
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 20,
                    color: chat?.isDisappearing == true
                        ? AppTheme.warningColor
                        : _SnapColors.textPrimary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Disappearing Messages',
                    style: TextStyle(
                      color: chat?.isDisappearing == true
                          ? AppTheme.warningColor
                          : _SnapColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (chat?.type == ChatType.group)
              const PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app, size: 20, color: AppTheme.errorColor),
                    SizedBox(width: 12),
                    Text('Leave Chat', style: TextStyle(color: AppTheme.errorColor)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDisappearingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: _SnapColors.divider,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer, size: 14, color: AppTheme.warningColor.withValues(alpha: 0.8)),
          const SizedBox(width: 6),
          Text(
            'Disappearing messages on',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.warningColor.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(String userId, String? typingText) {
    if (_chatProvider.isLoading && _chatProvider.messages.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: _SnapColors.ownBubble),
      );
    }

    final messages = _chatProvider.messages;
    final itemCount = messages.length + (typingText != null ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (typingText != null && index == 0) {
          return _TypingIndicatorBubble(
            typingUsers: _chatProvider.getTypingUsers(widget.chatId),
          );
        }

        final msgIndex = typingText != null ? index - 1 : index;
        final message = messages[msgIndex];
        final isMe = message.senderId == userId;
        final showDateSeparator = _shouldShowDateSeparator(messages, msgIndex);
        final showAvatar = !isMe &&
            _currentChat?.type == ChatType.group &&
            (msgIndex == messages.length - 1 ||
                messages[msgIndex + 1].senderId != message.senderId);
        final showSenderLabel = _shouldShowSenderLabel(messages, msgIndex, typingText != null);
        final senderLabelText = isMe ? 'Me' : (message.sender?.displayName ?? _currentChat?.displayName(userId) ?? 'User');

        if (message.isSnapMessage) {
          return Column(
            children: [
              if (showDateSeparator) _buildDateSeparator(message.createdAt),
              _SnapMessageBubble(
                message: message,
                isMe: isMe,
                chatDisplayName: _currentChat?.displayName(userId) ?? 'Someone',
              ),
            ],
          );
        }

        return Column(
          children: [
            if (showDateSeparator) _buildDateSeparator(message.createdAt),
            _MessageBubble(
              message: message,
              isMe: isMe,
              showAvatar: showAvatar,
              showSenderLabel: showSenderLabel,
              senderLabelText: senderLabelText,
              onReply: () => setState(() => _replyingTo = message),
              onRetry: message.status == MessageStatus.failed
                  ? () => _chatProvider.retrySendMessage(message.id)
                  : null,
              chatId: widget.chatId,
              isDisappearing: _currentChat?.isDisappearing ?? false,
            ),
          ],
        );
      },
    );
  }

  bool _shouldShowDateSeparator(List<Message> messages, int index) {
    if (index == messages.length - 1) return true;
    final current = messages[index].createdAt;
    final previous = messages[index + 1].createdAt;
    return !_isSameDay(current, previous);
  }

  bool _shouldShowSenderLabel(List<Message> messages, int index, bool hasTypingIndicator) {
    if (index == messages.length - 1) return true;
    final currentMessage = messages[index];
    final previousMessage = messages[index + 1];
    if (previousMessage.senderId != currentMessage.senderId) return true;
    if (!_isSameDay(currentMessage.createdAt, previousMessage.createdAt)) return true;
    return false;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    String text;

    if (_isSameDay(date, now)) {
      text = 'Today';
    } else if (_isSameDay(date, yesterday)) {
      text = 'Yesterday';
    } else if (now.difference(date).inDays < 7) {
      text = DateFormat('EEEE').format(date);
    } else {
      text = DateFormat('MMM d, yyyy').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _SnapColors.divider,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: _SnapColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: _SnapColors.otherBubble,
        border: Border(
          top: BorderSide(color: _SnapColors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: _SnapColors.ownBubble,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _replyingTo!.sender?.displayName ?? 'User',
                  style: const TextStyle(
                    color: _SnapColors.ownBubble,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyingTo!.type == MessageType.image
                      ? '📷 Photo'
                      : _replyingTo!.content,
                  style: const TextStyle(
                    color: _SnapColors.textMuted,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: _SnapColors.textMuted),
            onPressed: () => setState(() => _replyingTo = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    if (_isRecording) return _buildRecordingBar();

    final hasText = _messageController.text.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Camera button - white circle, OUTSIDE and LEFT of input bar
          GestureDetector(
            onTap: () => _pickAndSendMedia(ImageSource.camera),
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                size: 24,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Input bar pill with text field and mic/send inside
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: const Color(0xFF3A3A3C),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Text field
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      cursorColor: Colors.white,
                      style: const TextStyle(
                        color: _SnapColors.textPrimary,
                        fontSize: 15,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Send a chat',
                        hintStyle: TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.only(
                          left: 16,
                          right: 8,
                          top: 12,
                          bottom: 12,
                        ),
                      ),
                      maxLines: 5,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _sendMessage(),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  // Mic or Send button INSIDE the pill
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 6),
                    child: GestureDetector(
                      onTap: hasText ? _sendMessage : _startRecording,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: hasText ? const Color(0xFF0EADFF) : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          hasText ? Icons.arrow_upward_rounded : Icons.mic_none_rounded,
                          size: 20,
                          color: hasText ? Colors.white : const Color(0xFF8E8E93),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Emoji button
          GestureDetector(
            onTap: () => _showEmojiPicker(),
            child: const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Icon(
                Icons.sentiment_satisfied_alt_outlined,
                size: 28,
                color: Color(0xFF8E8E93),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Memories button (opens gallery/memories)
          GestureDetector(
            onTap: () => context.push('/memories'),
            child: const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Icon(
                Icons.photo_library_outlined,
                size: 28,
                color: Color(0xFF8E8E93),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Chat background button
          GestureDetector(
            onTap: _showBackgroundPicker,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Icon(
                Icons.wallpaper_outlined,
                size: 28,
                color: _currentChat?.backgroundUrl != null
                    ? _SnapColors.ownBubble
                    : const Color(0xFF8E8E93),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingBar() {
    return Padding(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        children: [
          // Cancel button
          GestureDetector(
            onTap: _cancelRecording,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFF2C2C2E),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 22, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          // Recording indicator + timer
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF3A3A3C)),
              ),
              child: Row(
                children: [
                  // Pulsing red dot
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.3, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    builder: (_, value, _) => Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: value),
                        shape: BoxShape.circle,
                      ),
                    ),
                    onEnd: () {},
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _formatDuration(_recordingSeconds),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Recording...',
                    style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Send button
          GestureDetector(
            onTap: _isSendingVoice ? null : _stopAndSendRecording,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFF0EADFF),
                shape: BoxShape.circle,
              ),
              child: _isSendingVoice
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.arrow_upward_rounded,
                      size: 24,
                      color: Colors.white,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEmojiPicker() {
    // Show emoji quick reactions bottom sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: _SnapColors.otherBubble,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _SnapColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Quick Reactions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _SnapColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: ['😀', '😂', '😍', '🥺', '😭', '🔥', '👍', '❤️', '💀', '🎉', '👀', '✨']
                    .map((emoji) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _messageController.text += emoji;
                      _messageController.selection = TextSelection.fromPosition(
                        TextPosition(offset: _messageController.text.length),
                      );
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _SnapColors.divider,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 28)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showDisappearingMessagesSheet() {
    final chat = _currentChat;
    final currentSetting = chat?.isDisappearing == true ? chat?.disappearAfter : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: _SnapColors.otherBubble,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _SnapColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Icon(Icons.timer_outlined, size: 48, color: AppTheme.warningColor),
            const SizedBox(height: 12),
            const Text(
              'Disappearing Messages',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _SnapColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'New messages will disappear after the selected time.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: _SnapColors.textMuted),
              ),
            ),
            const SizedBox(height: 24),
            _DisappearingOption(
              label: 'Off',
              isSelected: currentSetting == null,
              onTap: () {
                Navigator.pop(ctx);
                _chatProvider.updateDisappearingMessages(
                  widget.chatId,
                  isDisappearing: false,
                  disappearAfter: null,
                );
              },
            ),
            _DisappearingOption(
              label: '24 Hours',
              isSelected: currentSetting == 86400,
              onTap: () {
                Navigator.pop(ctx);
                _chatProvider.updateDisappearingMessages(
                  widget.chatId,
                  isDisappearing: true,
                  disappearAfter: 86400,
                );
              },
            ),
            _DisappearingOption(
              label: '7 Days',
              isSelected: currentSetting == 604800,
              onTap: () {
                Navigator.pop(ctx);
                _chatProvider.updateDisappearingMessages(
                  widget.chatId,
                  isDisappearing: true,
                  disappearAfter: 604800,
                );
              },
            ),
            _DisappearingOption(
              label: '90 Days',
              isSelected: currentSetting == 7776000,
              onTap: () {
                Navigator.pop(ctx);
                _chatProvider.updateDisappearingMessages(
                  widget.chatId,
                  isDisappearing: true,
                  disappearAfter: 7776000,
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showBackgroundPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _SnapColors.otherBubble,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => _BackgroundPickerSheet(
          scrollController: scrollCtrl,
          chatId: widget.chatId,
          currentBackgroundUrl: _currentChat?.backgroundUrl,
          onApply: (url) {
            Navigator.pop(ctx);
            _chatProvider.updateChatBackground(widget.chatId, backgroundUrl: url);
          },
          onRemove: () {
            Navigator.pop(ctx);
            _chatProvider.updateChatBackground(widget.chatId, backgroundUrl: null);
          },
        ),
      ),
    );
  }
}

/// Snapchat-style typing indicator bubble
class _TypingIndicatorBubble extends StatefulWidget {
  final List typingUsers;
  const _TypingIndicatorBubble({required this.typingUsers});

  @override
  State<_TypingIndicatorBubble> createState() => _TypingIndicatorBubbleState();
}

class _TypingIndicatorBubbleState extends State<_TypingIndicatorBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _SnapColors.otherBubble,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final delay = index * 0.2;
                    final t = (_controller.value + delay) % 1.0;
                    final scale = 0.5 + 0.5 * (t < 0.5 ? t * 2 : 2 - t * 2);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: _SnapColors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Snapchat-style message bubble
class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool showAvatar;
  final bool showSenderLabel;
  final String senderLabelText;
  final VoidCallback onReply;
  final VoidCallback? onRetry;
  final String chatId;
  final bool isDisappearing;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.showAvatar = false,
    this.showSenderLabel = false,
    this.senderLabelText = '',
    required this.onReply,
    this.onRetry,
    required this.chatId,
    this.isDisappearing = false,
  });

  @override
  Widget build(BuildContext context) {
    final isFailed = message.status == MessageStatus.failed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sender name label
          if (showSenderLabel)
            Padding(
              padding: const EdgeInsets.only(
                left: 4,
                bottom: 3,
                top: 8,
              ),
              child: Text(
                senderLabelText,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _SnapColors.textMuted,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe && showAvatar)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AvatarWidget(avatarUrl: message.sender?.avatarUrl, radius: 12),
                )
              else if (!isMe)
                const SizedBox(width: 32),
              if (isFailed && isMe)
                GestureDetector(
                  onTap: onRetry,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.error_outline, color: AppTheme.errorColor, size: 18),
                  ),
                ),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onLongPress: () => _showMessageOptions(context),
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.7,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Reply preview above bubble
                            if (message.replyTo != null) _buildReplyPreview(),
                            // Main bubble
                            Container(
                              padding: message.type == MessageType.image 
                                  ? const EdgeInsets.all(3)
                                  : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isFailed
                                    ? AppTheme.errorColor.withValues(alpha: 0.2)
                                    : isMe
                                        ? _SnapColors.ownBubble
                                        : _SnapColors.otherBubble,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(18),
                                  topRight: Radius.circular(18),
                                  bottomLeft: Radius.circular(4),
                                  bottomRight: Radius.circular(18),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Sender name in group chats (inside bubble)
                                  if (showAvatar && message.sender != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        message.sender!.displayName,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _SnapColors.ownBubble,
                                        ),
                                      ),
                                    ),
                                  _buildContent(context),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Footer OUTSIDE bubble
                    const SizedBox(height: 2),
                    _buildFooter(),
                    // Reactions below
                    if (message.reactions.isNotEmpty) _buildReactions(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe 
            ? _SnapColors.ownBubble.withValues(alpha: 0.3)
            : _SnapColors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: _SnapColors.ownBubble, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.replyTo!.senderName ?? 'User',
            style: const TextStyle(
              fontSize: 11, 
              fontWeight: FontWeight.w600,
              color: _SnapColors.ownBubble,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.replyTo!.content,
            style: TextStyle(
              fontSize: 12, 
              color: _SnapColors.textPrimary.withValues(alpha: 0.7),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (message.type) {
      case MessageType.image:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.network(
                  message.mediaUrl!,
                  width: 220,
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      width: 220,
                      height: 150,
                      decoration: BoxDecoration(
                        color: _SnapColors.otherBubble,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: _SnapColors.ownBubble,
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 220,
                    height: 150,
                    decoration: BoxDecoration(
                      color: _SnapColors.otherBubble,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.broken_image, color: _SnapColors.textMuted),
                  ),
                ),
              ),
            if (message.content.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  message.content,
                  style: const TextStyle(
                    fontSize: 15,
                    color: _SnapColors.textPrimary,
                  ),
                ),
              ),
            ],
          ],
        );
      case MessageType.audio:
        return _AudioMessagePlayer(
          audioUrl: message.mediaUrl ?? '',
          duration: message.duration ?? 0,
          isMe: isMe,
        );
      default:
        return Text(
          message.content,
          style: const TextStyle(
            fontSize: 15,
            color: _SnapColors.textPrimary,
          ),
        );
    }
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(
        left: 4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDisappearing) ...[
            Icon(
              Icons.timer,
              size: 10,
              color: _SnapColors.textMuted.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 3),
          ],
          Text(
            timeago.format(message.createdAt, locale: 'en_short'),
            style: const TextStyle(
              fontSize: 10,
              color: _SnapColors.textMuted,
            ),
          ),
          if (message.isEdited) ...[
            const SizedBox(width: 4),
            const Text(
              '• edited',
              style: TextStyle(
                fontSize: 10,
                color: _SnapColors.textMuted,
              ),
            ),
          ],
          if (isMe) ...[
            const SizedBox(width: 4),
            _MessageStatusIcon(status: message.status),
          ],
        ],
      ),
    );
  }

  Widget _buildReactions() {
    final grouped = <String, int>{};
    for (final r in message.reactions) {
      grouped[r.emoji] = (grouped[r.emoji] ?? 0) + 1;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: grouped.entries.map((entry) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _SnapColors.otherBubble,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 12)),
                if (entry.value > 1) ...[
                  const SizedBox(width: 2),
                  Text(
                    '${entry.value}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: _SnapColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showMessageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _SnapColors.otherBubble,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _SnapColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Quick reactions row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ['❤️', '😂', '😮', '😢', '😡', '👍'].map((emoji) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      ChatProvider().reactToMessage(
                        chatId: chatId,
                        messageId: message.id,
                        emoji: emoji,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _SnapColors.divider,
                        shape: BoxShape.circle,
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(color: _SnapColors.divider, height: 1),
            ListTile(
              leading: const Icon(Icons.reply, color: _SnapColors.textPrimary, size: 22),
              title: const Text('Reply', style: TextStyle(color: _SnapColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                onReply();
              },
            ),
            if (message.type == MessageType.text)
              ListTile(
                leading: const Icon(Icons.copy, color: _SnapColors.textPrimary, size: 22),
                title: const Text('Copy', style: TextStyle(color: _SnapColors.textPrimary)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: message.content));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
            if (isMe && message.status == MessageStatus.failed)
              ListTile(
                leading: const Icon(Icons.refresh, color: AppTheme.warningColor, size: 22),
                title: const Text('Retry', style: TextStyle(color: AppTheme.warningColor)),
                onTap: () {
                  Navigator.pop(ctx);
                  onRetry?.call();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Message status indicator
class _MessageStatusIcon extends StatelessWidget {
  final MessageStatus status;
  const _MessageStatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: _SnapColors.textMuted),
        );
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 12, color: _SnapColors.textMuted);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 12, color: _SnapColors.textMuted);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 12, color: _SnapColors.ownBubble);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 12, color: AppTheme.errorColor);
    }
  }
}

/// Disappearing messages option
class _DisappearingOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DisappearingOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      title: Text(label, style: const TextStyle(color: _SnapColors.textPrimary)),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: _SnapColors.ownBubble)
          : const Icon(Icons.circle_outlined, color: _SnapColors.textMuted),
      onTap: onTap,
    );
  }
}

/// Snapchat-style snap message (centered)
class _SnapMessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final String chatDisplayName;

  static const Color snapImageColor = Color(0xFFFF0044);
  static const Color snapVideoColor = Color(0xFF9C27B0);

  const _SnapMessageBubble({
    required this.message,
    required this.isMe,
    required this.chatDisplayName,
  });

  @override
  Widget build(BuildContext context) {
    final snapData = message.snapData;
    if (snapData == null) return const SizedBox.shrink();

    final color = snapData.isImage ? snapImageColor : snapVideoColor;
    final IconData icon;
    final String label;
    final bool isFilled;
    final bool showReplayHint;

    if (isMe) {
      showReplayHint = false;
      switch (snapData.status) {
        case SnapStatus.sent:
          icon = Icons.send;
          label = 'Sent';
          isFilled = true;
          break;
        case SnapStatus.delivered:
          icon = Icons.send_outlined;
          label = 'Delivered';
          isFilled = false;
          break;
        case SnapStatus.opened:
          icon = Icons.crop_square_outlined;
          label = 'Opened';
          isFilled = false;
          break;
        case SnapStatus.replayed:
          icon = Icons.replay;
          label = 'Replayed';
          isFilled = false;
          break;
        case SnapStatus.screenshot:
          icon = Icons.warning_rounded;
          label = 'Screenshot!';
          isFilled = true;
          break;
      }
    } else {
      switch (snapData.status) {
        case SnapStatus.sent:
        case SnapStatus.delivered:
          icon = Icons.crop_square;
          label = 'New Snap';
          isFilled = true;
          showReplayHint = false;
          break;
        case SnapStatus.opened:
          icon = Icons.crop_square_outlined;
          label = 'Viewed';
          isFilled = false;
          showReplayHint = true;
          break;
        case SnapStatus.replayed:
          icon = Icons.replay;
          label = 'Replayed';
          isFilled = false;
          showReplayHint = false;
          break;
        case SnapStatus.screenshot:
          icon = Icons.warning_rounded;
          label = 'Screenshot!';
          isFilled = true;
          showReplayHint = false;
          break;
      }
    }

    final displayColor = snapData.isScreenshot ? snapImageColor : color;

    return GestureDetector(
      onTap: () => _handleTap(context, snapData),
      onLongPress: () => _handleReplay(context, snapData),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isFilled ? displayColor : Colors.transparent,
                    border: isFilled ? null : Border.all(color: displayColor, width: 2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: isFilled ? Colors.white : displayColor,
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: displayColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (showReplayHint)
                      const Text(
                        'Hold to replay',
                        style: TextStyle(
                          color: _SnapColors.textMuted,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              timeago.format(message.createdAt, locale: 'en_short'),
              style: const TextStyle(fontSize: 10, color: _SnapColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTap(BuildContext context, SnapMessageData snapData) {
    if (snapData.snapId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid snap')),
      );
      return;
    }

    if (isMe) {
      final statusText = switch (snapData.status) {
        SnapStatus.sent => 'Snap sent, waiting for delivery',
        SnapStatus.delivered => 'Snap delivered, waiting to be opened',
        SnapStatus.opened => 'Snap has been opened',
        SnapStatus.replayed => 'Snap was replayed',
        SnapStatus.screenshot => 'Recipient took a screenshot!',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(statusText),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (snapData.status == SnapStatus.sent || snapData.status == SnapStatus.delivered) {
      _openAndViewSnap(context, snapData);
    } else if (snapData.status == SnapStatus.opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Long press to replay this snap'),
          duration: Duration(seconds: 2),
        ),
      );
    } else if (snapData.status == SnapStatus.replayed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already replayed'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleReplay(BuildContext context, SnapMessageData snapData) {
    if (snapData.snapId.isEmpty) return;

    if (isMe) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You sent this snap'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (snapData.status == SnapStatus.sent || snapData.status == SnapStatus.delivered) {
      _openAndViewSnap(context, snapData);
      return;
    }

    if (snapData.status == SnapStatus.replayed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already replayed'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (snapData.status != SnapStatus.opened) {
      return;
    }

    HapticFeedback.mediumImpact();
    _openAndViewSnap(context, snapData, isReplay: true);
  }

  Future<void> _openAndViewSnap(BuildContext context, SnapMessageData snapData, {bool isReplay = false}) async {
    if (snapData.snapId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid snap')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: _SnapColors.ownBubble),
      ),
    );

    try {
      final api = ApiService();
      final response = await api.openSnap(snapData.snapId);
      
      if (context.mounted) Navigator.pop(context);
      
      final data = response.data['data'];
      if (data == null) {
        throw Exception('Invalid response: missing data');
      }
      
      final snap = data['snap'];
      if (snap == null) {
        throw Exception('Invalid response: missing snap object');
      }
      
      final viewDuration = data['viewDuration'] as int? ?? 5;
      final mediaUrl = snap['mediaUrl'] as String?;
      final mediaType = snap['mediaType'] as String? ?? 'IMAGE';
      
      if (mediaUrl == null || mediaUrl.isEmpty) {
        throw Exception('Snap media URL not available');
      }

      if (context.mounted) {
        _showSnapViewer(
          context,
          mediaUrl: mediaUrl,
          isVideo: mediaType == 'VIDEO',
          viewDuration: viewDuration,
          snapId: snapData.snapId,
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      
      if (context.mounted) {
        String errorMessage;
        if (e is DioException) {
          final statusCode = e.response?.statusCode;
          final responseData = e.response?.data;
          String? serverMsg;
          if (responseData is Map) {
            serverMsg = responseData['message'] as String? ?? responseData['error'] as String?;
          }
          if (serverMsg != null && serverMsg.isNotEmpty) {
            errorMessage = serverMsg;
          } else if (statusCode == 404) {
            errorMessage = 'Snap not found';
          } else if (statusCode == 403) {
            errorMessage = 'Snap already viewed or expired';
          } else {
            errorMessage = 'Could not open snap';
          }
        } else {
          final errorStr = e.toString().toLowerCase();
          if (errorStr.contains('already viewed') || errorStr.contains('already opened')) {
            errorMessage = 'Snap already viewed';
          } else if (errorStr.contains('expired')) {
            errorMessage = 'Snap has expired';
          } else if (errorStr.contains('not found')) {
            errorMessage = 'Snap not found';
          } else {
            errorMessage = 'Could not open snap';
          }
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showSnapViewer(
    BuildContext context, {
    required String mediaUrl,
    required bool isVideo,
    required int viewDuration,
    required String snapId,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black,
      builder: (ctx) => _SnapViewerDialog(
        mediaUrl: mediaUrl,
        isVideo: isVideo,
        viewDuration: viewDuration,
        snapId: snapId,
      ),
    );
  }
}

/// Full-screen snap viewer with countdown timer
class _SnapViewerDialog extends StatefulWidget {
  final String mediaUrl;
  final bool isVideo;
  final int viewDuration;
  final String snapId;

  const _SnapViewerDialog({
    required this.mediaUrl,
    required this.isVideo,
    required this.viewDuration,
    required this.snapId,
  });

  @override
  State<_SnapViewerDialog> createState() => _SnapViewerDialogState();
}

class _SnapViewerDialogState extends State<_SnapViewerDialog> {
  late int _secondsRemaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.viewDuration;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _secondsRemaining--;
        });
        if (_secondsRemaining <= 0) {
          timer.cancel();
          Navigator.of(context).pop();
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: widget.isVideo
                  ? _buildVideoPlaceholder()
                  : CachedNetworkImage(
                      imageUrl: widget.mediaUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(color: _SnapColors.ownBubble),
                      ),
                      errorWidget: (context, url, error) => const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image, size: 64, color: _SnapColors.textMuted),
                          SizedBox(height: 16),
                          Text(
                            'Failed to load snap',
                            style: TextStyle(color: _SnapColors.textMuted),
                          ),
                        ],
                      ),
                    ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: _secondsRemaining / widget.viewDuration,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_secondsRemaining}s',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 32,
              left: 0,
              right: 0,
              child: const Center(
                child: Text(
                  'Tap anywhere to close',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.play_circle_outline, size: 80, color: Colors.white),
        const SizedBox(height: 16),
        const Text(
          'Video Snap',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        const SizedBox(height: 8),
        Text(
          'Duration: ${widget.viewDuration}s',
          style: const TextStyle(color: Colors.white54),
        ),
      ],
    );
  }
}

/// Audio message player widget with play/pause, progress, and duration
class _AudioMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final int duration; // seconds from server
  final bool isMe;

  const _AudioMessagePlayer({
    required this.audioUrl,
    required this.duration,
    required this.isMe,
  });

  @override
  State<_AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<_AudioMessagePlayer> {
  late final ja.AudioPlayer _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  StreamSubscription? _posSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _durSub;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _player = ja.AudioPlayer();
    _totalDuration = Duration(seconds: widget.duration);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final dur = await _player.setUrl(widget.audioUrl);
      if (dur != null && mounted) {
        setState(() {
          _totalDuration = dur;
        });
      } else if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('[AUDIO] load error: $e');
      if (mounted) setState(() => _hasError = true);
      return;
    }

    _posSub = _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _stateSub = _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state.playing);
        if (state.processingState == ja.ProcessingState.completed) {
          _player.seek(Duration.zero);
          _player.pause();
        }
      }
    });
    _durSub = _player.durationStream.listen((dur) {
      if (dur != null && mounted) setState(() => _totalDuration = dur);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_hasError) return;
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalDuration.inMilliseconds > 0
        ? (_position.inMilliseconds / _totalDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final accentColor = widget.isMe ? Colors.white : const Color(0xFF0EADFF);
    final trackBg = widget.isMe
        ? Colors.white.withValues(alpha: 0.25)
        : const Color(0xFF3A3A3C);

    if (_hasError) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 18, color: _SnapColors.textMuted),
          SizedBox(width: 6),
          Text('Audio unavailable',
              style: TextStyle(fontSize: 13, color: _SnapColors.textMuted)),
        ],
      );
    }

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          // Play/pause button
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: accentColor,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Progress bar + time
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: trackBg,
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isPlaying
                      ? _fmt(_position)
                      : _fmt(_totalDuration),
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.isMe
                        ? Colors.white.withValues(alpha: 0.7)
                        : _SnapColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.mic,
            size: 16,
            color: accentColor.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}

/// Background picker sheet that loads memories/snap gallery
class _BackgroundPickerSheet extends StatefulWidget {
  final ScrollController scrollController;
  final String chatId;
  final String? currentBackgroundUrl;
  final void Function(String url) onApply;
  final VoidCallback onRemove;

  const _BackgroundPickerSheet({
    required this.scrollController,
    required this.chatId,
    this.currentBackgroundUrl,
    required this.onApply,
    required this.onRemove,
  });

  @override
  State<_BackgroundPickerSheet> createState() => _BackgroundPickerSheetState();
}

class _BackgroundPickerSheetState extends State<_BackgroundPickerSheet> {
  final MemoryProvider _memoryProvider = MemoryProvider();
  bool _loading = true;
  List<Memory> _memories = [];
  String? _selectedUrl;

  @override
  void initState() {
    super.initState();
    _selectedUrl = widget.currentBackgroundUrl;
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    await _memoryProvider.loadMemories(refresh: true);
    if (mounted) {
      setState(() {
        _memories = _memoryProvider.memories
            .where((m) => m.isImage && !m.isMyEyesOnly)
            .toList();
        _loading = false;
      });
    }
  }

  bool get _hasChanges => _selectedUrl != widget.currentBackgroundUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: _SnapColors.textMuted,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        const Icon(Icons.wallpaper_outlined, size: 36, color: _SnapColors.ownBubble),
        const SizedBox(height: 8),
        const Text(
          'Chat Background',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _SnapColors.textPrimary),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap to select, then apply',
          style: TextStyle(fontSize: 13, color: _SnapColors.textMuted),
        ),
        const SizedBox(height: 12),
        // Action buttons row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Remove button
              if (widget.currentBackgroundUrl != null)
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onRemove,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _SnapColors.divider,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: AppTheme.errorColor),
                          SizedBox(width: 6),
                          Text('Remove', style: TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.w600, fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                ),
              if (widget.currentBackgroundUrl != null) const SizedBox(width: 10),
              // Apply button
              Expanded(
                child: GestureDetector(
                  onTap: _hasChanges && _selectedUrl != null
                      ? () => widget.onApply(_selectedUrl!)
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _hasChanges && _selectedUrl != null
                          ? _SnapColors.ownBubble
                          : _SnapColors.divider,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 18,
                          color: _hasChanges && _selectedUrl != null
                              ? Colors.white
                              : _SnapColors.textMuted),
                        const SizedBox(width: 6),
                        Text(
                          'Apply Background',
                          style: TextStyle(
                            color: _hasChanges && _selectedUrl != null
                                ? Colors.white
                                : _SnapColors.textMuted,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Memory grid
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _SnapColors.ownBubble))
              : _memories.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.photo_library_outlined, size: 48,
                              color: _SnapColors.textMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          const Text('No memories yet',
                              style: TextStyle(color: _SnapColors.textMuted, fontSize: 16)),
                          const SizedBox(height: 4),
                          const Text('Save some snaps to use as backgrounds',
                              style: TextStyle(color: _SnapColors.textMuted, fontSize: 13)),
                        ],
                      ),
                    )
                  : GridView.builder(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 3,
                        crossAxisSpacing: 3,
                        childAspectRatio: 0.56,
                      ),
                      itemCount: _memories.length,
                      itemBuilder: (context, index) {
                        final memory = _memories[index];
                        final isSelected = _selectedUrl == memory.mediaUrl;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _selectedUrl = memory.mediaUrl);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? _SnapColors.ownBubble : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(7),
                                  child: Image.network(
                                    memory.mediaUrl,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.high,
                                    loadingBuilder: (_, child, progress) {
                                      if (progress == null) return child;
                                      return Container(
                                        color: _SnapColors.divider,
                                        child: const Center(
                                          child: SizedBox(width: 20, height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: _SnapColors.textMuted)),
                                        ),
                                      );
                                    },
                                    errorBuilder: (_, __, ___) => Container(
                                      color: _SnapColors.divider,
                                      child: const Icon(Icons.broken_image, color: _SnapColors.textMuted),
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Positioned(
                                    top: 6, right: 6,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: _SnapColors.ownBubble,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.check, color: Colors.white, size: 16),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
