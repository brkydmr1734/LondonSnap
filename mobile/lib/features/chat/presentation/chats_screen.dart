import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/chat/models/chat_models.dart';
import 'package:londonsnaps/features/chat/providers/chat_provider.dart';
import 'package:londonsnaps/features/auth/providers/auth_provider.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';
import 'package:londonsnaps/shared/widgets/notification_bell.dart';

// Snapchat color palette
class _SnapColors {
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF1C1C1E);
  static const Color snapRed = Color(0xFFFF0044);
  static const Color snapPurple = Color(0xFF9C27B0);
  static const Color snapBlue = Color(0xFF0EADFF);
  static const Color onlineGreen = Color(0xFF4CAF50);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color divider = Color(0x14FFFFFF);
  static const Color searchBg = Color(0xFF1C1C1E);
  static const Color yellowRing = Color(0xFFFFFC00);
  static const Color yellowRingEnd = Color(0xFFFFD700);
}

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen>
    with SingleTickerProviderStateMixin {
  final ChatProvider _chatProvider = ChatProvider();
  final AuthProvider _authProvider = AuthProvider();
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  late AnimationController _searchAnimController;
  late Animation<double> _searchAnimation;

  @override
  void initState() {
    super.initState();
    _chatProvider.addListener(_onUpdate);
    _authProvider.addListener(_onUpdate);
    _chatProvider.init();
    _chatProvider.loadChats();
    _chatProvider.reconnectWebSocket();

    _searchAnimController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _searchAnimation = CurvedAnimation(
      parent: _searchAnimController,
      curve: Curves.easeOutCubic,
    );
  }

  void _onUpdate() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _chatProvider.removeListener(_onUpdate);
    _authProvider.removeListener(_onUpdate);
    _searchController.dispose();
    _searchAnimController.dispose();
    super.dispose();
  }

  List<Chat> get _filteredChats {
    if (_searchController.text.isEmpty) return _chatProvider.chats;
    final query = _searchController.text.toLowerCase();
    final userId = _authProvider.currentUser?.id ?? '';
    return _chatProvider.chats.where((chat) {
      return chat.displayName(userId).toLowerCase().contains(query);
    }).toList();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (_isSearching) {
        _searchAnimController.forward();
      } else {
        _searchAnimController.reverse();
        _searchController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SnapColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // User avatar with yellow gradient ring
          GestureDetector(
            onTap: () => context.go('/profile'),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [_SnapColors.yellowRing, _SnapColors.yellowRingEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _SnapColors.yellowRing.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(2),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _SnapColors.background,
                ),
                padding: const EdgeInsets.all(1),
                child: _authProvider.currentUser?.avatarUrl != null &&
                        _authProvider.currentUser!.avatarUrl!.isNotEmpty
                    ? AvatarWidget(
                        avatarUrl: _authProvider.currentUser!.avatarUrl,
                        radius: 14,
                      )
                    : CircleAvatar(
                        radius: 14,
                        backgroundColor: AppTheme.primaryColor,
                        child: Text(
                          (_authProvider.currentUser?.displayName ?? '?')
                              .split(' ')
                              .map((w) => w.isNotEmpty ? w[0] : '')
                              .take(2)
                              .join()
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Search icon
          IconButton(
            icon: const Icon(Icons.search, color: _SnapColors.textPrimary, size: 24),
            onPressed: _toggleSearch,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const Spacer(),
          // Center title
          const Text(
            'Chat',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _SnapColors.textPrimary,
            ),
          ),
          const Spacer(),
          // Notification bell
          const NotificationBell(),
          // New chat icon with + badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.chat_bubble_outline,
                  color: _SnapColors.textPrimary,
                  size: 24,
                ),
                onPressed: () => context.push('/friends'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: _SnapColors.snapBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.add, size: 10, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return SizeTransition(
      sizeFactor: _searchAnimation,
      axisAlignment: -1,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _SnapColors.searchBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: _SnapColors.textSecondary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: false,
                style: const TextStyle(color: _SnapColors.textPrimary, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Search',
                  hintStyle: TextStyle(color: _SnapColors.textSecondary),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() {});
                },
                child: const Icon(Icons.close, color: _SnapColors.textSecondary, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_chatProvider.isLoading && _chatProvider.chats.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: _SnapColors.snapBlue),
      );
    }

    if (_filteredChats.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => _chatProvider.loadChats(),
      color: _SnapColors.snapBlue,
      backgroundColor: _SnapColors.surface,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 4),
        itemCount: _filteredChats.length,
        separatorBuilder: (context, index) => Container(
          margin: const EdgeInsets.only(left: 68),
          height: 0.5,
          color: _SnapColors.divider,
        ),
        itemBuilder: (context, index) {
          final chat = _filteredChats[index];
          final userId = _authProvider.currentUser?.id ?? '';
          final typingText = _chatProvider.getTypingText(chat.id);
          return _ChatListItem(
            chat: chat,
            currentUserId: userId,
            typingText: typingText,
            chatProvider: _chatProvider,
            onTap: () => context.push('/chats/${chat.id}'),
            onLongPress: () => _showChatOptions(chat),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _SnapColors.surface,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 36,
              color: _SnapColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Friends Yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _SnapColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add friends to start chatting!',
            style: TextStyle(
              fontSize: 14,
              color: _SnapColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => context.push('/friends'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: _SnapColors.snapBlue,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Text(
                'Start a Chat',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showChatOptions(Chat chat) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _SnapColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _SnapColors.textSecondary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            _buildOptionTile(
              icon: chat.isMuted ? Icons.notifications : Icons.notifications_off,
              label: chat.isMuted ? 'Unmute' : 'Mute',
              onTap: () {
                _chatProvider.muteChat(chat.id);
                Navigator.pop(context);
              },
            ),
            if (chat.type == ChatType.group)
              _buildOptionTile(
                icon: Icons.exit_to_app,
                label: 'Leave Chat',
                isDestructive: true,
                onTap: () {
                  _chatProvider.leaveChat(chat.id);
                  Navigator.pop(context);
                },
              ),
            _buildOptionTile(
              icon: Icons.delete_outline,
              label: 'Delete Chat',
              isDestructive: true,
              onTap: () {
                Navigator.pop(context);
                _showDeleteChatDialog(chat);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? _SnapColors.snapRed : _SnapColors.textPrimary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }

  void _showDeleteChatDialog(Chat chat) {
    final userId = _authProvider.currentUser?.id ?? '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _SnapColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Chat', style: TextStyle(color: _SnapColors.textPrimary)),
        content: Text(
          'Delete your conversation with ${chat.displayName(userId)}? This action cannot be undone.',
          style: const TextStyle(color: _SnapColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _SnapColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _chatProvider.deleteChat(chat.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Chat deleted'),
                  backgroundColor: _SnapColors.surface,
                ),
              );
            },
            child: const Text('Delete', style: TextStyle(color: _SnapColors.snapRed)),
          ),
        ],
      ),
    );
  }
}

/// Snapchat-style chat list item
class _ChatListItem extends StatelessWidget {
  final Chat chat;
  final String currentUserId;
  final String? typingText;
  final ChatProvider chatProvider;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ChatListItem({
    required this.chat,
    required this.currentUserId,
    required this.typingText,
    required this.chatProvider,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = chat.unreadCount > 0;
    final displayName = chat.displayName(currentUserId);
    final lastMessage = chat.lastMessage;
    final otherParticipants = chat.participants
        .where((p) => p.user.id != currentUserId)
        .toList();
    final isOnline = otherParticipants.isNotEmpty &&
        (chatProvider.isUserOnline(otherParticipants.first.user.id) ||
            otherParticipants.first.user.isOnline);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: _SnapColors.surface.withValues(alpha: 0.5),
        highlightColor: _SnapColors.surface.withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Avatar with online indicator (NO gradient ring)
              _buildAvatar(otherParticipants, isOnline),
              const SizedBox(width: 12),
              // Content columns
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Display name
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                              color: _SnapColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (chat.isMuted) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.notifications_off,
                            size: 12,
                            color: _SnapColors.textSecondary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Row 2: Message preview with snap icons
                    _buildSubtitle(lastMessage, hasUnread),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Right side: timestamp + chevron + unread dot
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    lastMessage != null ? _formatTime(lastMessage.createdAt) : '',
                    style: const TextStyle(
                      fontSize: 11,
                      color: _SnapColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Unread blue dot (Snapchat uses dot, not count)
                      if (hasUnread)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: const BoxDecoration(
                            color: _SnapColors.snapBlue,
                            shape: BoxShape.circle,
                          ),
                        ),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: _SnapColors.textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(List<ChatParticipant> otherParticipants, bool isOnline) {
    return Stack(
      children: [
        // Simple circular avatar (NO gradient ring - that's for stories)
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _SnapColors.divider,
              width: 1,
            ),
          ),
          child: ClipOval(
            child: AvatarWidget(
              avatarUrl: otherParticipants.isNotEmpty
                  ? otherParticipants.first.user.avatarUrl
                  : null,
              radius: 22,
            ),
          ),
        ),
        // Online indicator
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _SnapColors.onlineGreen,
                shape: BoxShape.circle,
                border: Border.all(color: _SnapColors.background, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSubtitle(Message? lastMessage, bool hasUnread) {
    // Show typing indicator if someone is typing
    if (typingText != null) {
      return Row(
        children: [
          Text(
            'typing...',
            style: TextStyle(
              color: _SnapColors.snapBlue,
              fontStyle: FontStyle.italic,
              fontSize: 13,
            ),
          ),
        ],
      );
    }

    // Show snap message preview with Snapchat-style indicators
    if (lastMessage != null && lastMessage.isSnapMessage) {
      return _SnapPreview(
        message: lastMessage,
        isFromMe: lastMessage.senderId == currentUserId,
      );
    }

    // Show regular message preview with blue arrow for text messages
    if (lastMessage != null) {
      final isFromMe = lastMessage.senderId == currentUserId;
      return Row(
        children: [
          // Blue arrow indicator for text messages
          Icon(
            isFromMe ? Icons.arrow_forward : Icons.arrow_back,
            size: 12,
            color: hasUnread ? _SnapColors.snapBlue : _SnapColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _getMessagePreview(lastMessage),
              style: TextStyle(
                fontSize: 13,
                color: hasUnread ? _SnapColors.textPrimary : _SnapColors.textSecondary,
                fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Text(
      'Start chatting',
      style: TextStyle(
        fontSize: 13,
        color: _SnapColors.textSecondary,
      ),
    );
  }

  String _getMessagePreview(Message message) {
    switch (message.type) {
      case MessageType.image:
        return 'Photo';
      case MessageType.video:
        return 'Video';
      case MessageType.audio:
        return '🎤 Voice Message';
      case MessageType.sticker:
        return 'Sticker';
      case MessageType.location:
        return 'Location';
      case MessageType.system:
        return message.content;
      case MessageType.snap:
        return 'Snap';
      default:
        return message.content;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return 'now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d';
    } else {
      return '${time.day}/${time.month}';
    }
  }
}

/// Snapchat-style snap message preview for chat list
class _SnapPreview extends StatelessWidget {
  final Message message;
  final bool isFromMe;

  const _SnapPreview({
    required this.message,
    required this.isFromMe,
  });

  @override
  Widget build(BuildContext context) {
    final snapData = message.snapData;
    if (snapData == null) {
      return Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _SnapColors.snapRed,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Snap',
            style: TextStyle(color: _SnapColors.snapRed, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }

    final isImage = snapData.isImage;
    final baseColor = isImage ? _SnapColors.snapRed : _SnapColors.snapPurple;

    Widget icon;
    String label;
    Color color = baseColor;

    if (snapData.isScreenshot) {
      // Screenshot warning
      icon = Icon(Icons.warning_amber_rounded, size: 14, color: _SnapColors.snapRed);
      label = 'Screenshot!';
      color = _SnapColors.snapRed;
    } else if (isFromMe) {
      // Sender view - show send status with arrows
      switch (snapData.status) {
        case SnapStatus.sent:
          icon = _buildArrowIcon(filled: true, color: baseColor);
          label = 'Sent';
          break;
        case SnapStatus.delivered:
          icon = _buildArrowIcon(filled: false, color: baseColor);
          label = 'Delivered';
          break;
        case SnapStatus.opened:
        case SnapStatus.replayed:
          icon = _buildSquareIcon(filled: false, color: baseColor);
          label = 'Opened';
          break;
        default:
          icon = _buildArrowIcon(filled: true, color: baseColor);
          label = 'Sent';
      }
    } else {
      // Recipient view - show receive status with squares
      switch (snapData.status) {
        case SnapStatus.sent:
        case SnapStatus.delivered:
          // New snap - filled square
          icon = _buildSquareIcon(filled: true, color: baseColor);
          label = 'New Snap';
          break;
        case SnapStatus.opened:
        case SnapStatus.replayed:
          // Opened snap - hollow square
          icon = _buildSquareIcon(filled: false, color: baseColor);
          label = 'Opened';
          break;
        default:
          icon = _buildSquareIcon(filled: true, color: baseColor);
          label = 'Snap';
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildSquareIcon({required bool filled, required Color color}) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: filled ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(2),
        border: filled ? null : Border.all(color: color, width: 1.5),
      ),
    );
  }

  Widget _buildArrowIcon({required bool filled, required Color color}) {
    return Transform.rotate(
      angle: -0.5, // Slight upward angle like Snapchat
      child: Icon(
        filled ? Icons.send : Icons.send_outlined,
        size: 12,
        color: color,
      ),
    );
  }
}
