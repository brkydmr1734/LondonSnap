import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/chat/providers/chat_provider.dart';
import 'package:londonsnaps/features/social/models/social_models.dart';
import 'package:londonsnaps/features/social/providers/social_provider.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:londonsnaps/core/config/app_config.dart';

const _kMapboxToken = AppConfig.mapboxAccessToken;

// Snapchat brand colors
const _kSnapchatYellow = Color(0xFFFFFC00);
const _kSnapchatGold = Color(0xFFFFD700);
const _kSnapchatBlue = Color(0xFF0EADFF);

class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  final SocialProvider _provider = SocialProvider();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  double _scrollOffset = 0;
  bool _showTitleInAppBar = false;
  bool _isLoadingProfile = true;
  String? _profileError;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _provider.addListener(_onUpdate);
    _loadProfile();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final shouldShowTitle = offset > 200;
    if (shouldShowTitle != _showTitleInAppBar) {
      setState(() {
        _showTitleInAppBar = shouldShowTitle;
        _scrollOffset = offset;
      });
    } else if (offset != _scrollOffset) {
      setState(() => _scrollOffset = offset);
    }
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoadingProfile = true;
      _profileError = null;
    });
    await _provider.loadProfile(widget.userId);
    if (mounted) {
      setState(() {
        _isLoadingProfile = false;
        _profileError = _provider.error;
      });
    }
  }

  void _onUpdate() {
    if (mounted) {
      setState(() {});
      if (_provider.selectedProfile != null && !_provider.isLoading) {
        _fadeController.forward();
      }
    }
  }

  @override
  void dispose() {
    _provider.removeListener(_onUpdate);
    _scrollController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _provider.selectedProfile;

    if (_isLoadingProfile) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: _buildLoadingSkeleton(),
      );
    }

    if (_profileError != null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: _BackButton(onTap: () => context.pop()),
        ),
        body: _ErrorState(
          message: _profileError!,
          onRetry: () => _loadProfile(),
        ),
      );
    }

    if (profile == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: _BackButton(onTap: () => context.pop()),
        ),
        body: const _EmptyState(),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // SliverAppBar with collapsing header
            SliverAppBar(
              expandedHeight: 80,
              pinned: true,
              backgroundColor: AppTheme.backgroundColor,
              elevation: 0,
              leading: _BackButton(onTap: () => context.pop()),
              title: AnimatedOpacity(
                opacity: _showTitleInAppBar ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  profile.displayName,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
              ),
              actions: [
                _MoreMenuButton(
                  onBlock: () => _blockUser(),
                  onRemove: () => _removeFriend(),
                  onReport: () => _showReportDialog(),
                ),
              ],
            ),

            // Profile Header
            SliverToBoxAdapter(
              child: _ProfileHeader(profile: profile),
            ),

            // Action Buttons
            SliverToBoxAdapter(
              child: _ActionButtonsRow(
                profile: profile,
                onSendMessage: () => _startChatWith(profile),
                onSendSnap: () => context.go('/camera'),
                onMore: () => _showMoreOptions(),
              ),
            ),

            // Friendship Info Card
            SliverToBoxAdapter(
              child: _FriendshipInfoCard(profile: profile),
            ),

            // Mutual Friends Card
            if (profile.mutualFriends.isNotEmpty)
              SliverToBoxAdapter(
                child: _MutualFriendsCard(
                  mutualFriends: profile.mutualFriends,
                  onTapFriend: (id) => context.push('/profile/$id'),
                ),
              ),

            // Snap Map Section
            SliverToBoxAdapter(
              child: _SnapMapCard(
                profile: profile,
                onTapMap: () => context.push('/map'),
              ),
            ),

            // Saved in Chat Section
            const SliverToBoxAdapter(
              child: _SavedInChatCard(),
            ),

            // Stories Section
            const SliverToBoxAdapter(
              child: _StoriesCard(),
            ),

            // Add Friend Button (if not friends)
            if (profile.friendshipStatus != FriendshipStatus.accepted)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _FriendshipActionButton(
                    profile: profile,
                    onAdd: () => _provider.sendFriendRequest(widget.userId),
                    onUnblock: () => _provider.unblockUser(widget.userId),
                  ),
                ),
              ),

            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _BackButton(onTap: () => context.pop()),
                const Spacer(),
              ],
            ),
          ),
          const SizedBox(height: 40),
          // Avatar skeleton
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.surfaceColor.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          // Name skeleton
          Container(
            width: 150,
            height: 24,
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 12),
          // Username skeleton
          Container(
            width: 100,
            height: 16,
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 32),
          // Buttons skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                3,
                (i) => Container(
                  width: 80,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startChatWith(UserProfile profile) async {
    final chatProvider = ChatProvider();
    final chat = await chatProvider.createChat(memberIds: [profile.id]);
    if (mounted && chat != null) {
      context.push('/chats/${chat.id}');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(chatProvider.error ?? 'Failed to start chat'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  void _blockUser() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Block User', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Are you sure you want to block ${_provider.selectedProfile?.displayName}?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _provider.blockUser(widget.userId);
              context.pop();
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  void _removeFriend() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Friend', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Remove ${_provider.selectedProfile?.displayName} from your friends?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _provider.removeFriend(widget.userId);
              context.pop();
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showReportDialog() {
    String? selectedReason;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Report User', style: TextStyle(color: AppTheme.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Why are you reporting this user?',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 16),
                ...['Spam', 'Harassment', 'Inappropriate content', 'Fake profile', 'Other']
                    .map((reason) => _ReportReasonTile(
                          reason: reason,
                          isSelected: selectedReason == reason,
                          onTap: () => setDialogState(() => selectedReason = reason),
                        )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: selectedReason != null
                  ? () {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Report submitted. Thank you.'),
                          backgroundColor: AppTheme.successColor,
                        ),
                      );
                    }
                  : null,
              child: Text(
                'Report',
                style: TextStyle(
                  color: selectedReason != null ? AppTheme.errorColor : AppTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _BottomSheetOption(
              icon: Icons.block,
              label: 'Block User',
              isDestructive: true,
              onTap: () {
                Navigator.pop(ctx);
                _blockUser();
              },
            ),
            if (_provider.selectedProfile?.friendshipStatus == FriendshipStatus.accepted)
              _BottomSheetOption(
                icon: Icons.person_remove,
                label: 'Remove Friend',
                isDestructive: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _removeFriend();
                },
              ),
            _BottomSheetOption(
              icon: Icons.flag,
              label: 'Report',
              onTap: () {
                Navigator.pop(ctx);
                _showReportDialog();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// BACK BUTTON
// ─────────────────────────────────────────────────────────────────

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor.withValues(alpha: 0.8),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppTheme.textPrimary),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// MORE MENU BUTTON
// ─────────────────────────────────────────────────────────────────

class _MoreMenuButton extends StatelessWidget {
  final VoidCallback onBlock;
  final VoidCallback onRemove;
  final VoidCallback onReport;

  const _MoreMenuButton({
    required this.onBlock,
    required this.onRemove,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'block') onBlock();
        if (v == 'remove') onRemove();
        if (v == 'report') onReport();
      },
      color: AppTheme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor.withValues(alpha: 0.8),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.more_horiz, size: 20, color: AppTheme.textPrimary),
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'block',
          child: Row(
            children: [
              Icon(Icons.block, size: 20, color: AppTheme.errorColor),
              SizedBox(width: 12),
              Text('Block User', style: TextStyle(color: AppTheme.errorColor)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.person_remove, size: 20, color: AppTheme.textSecondary),
              SizedBox(width: 12),
              Text('Remove Friend', style: TextStyle(color: AppTheme.textSecondary)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'report',
          child: Row(
            children: [
              Icon(Icons.flag, size: 20, color: AppTheme.textSecondary),
              SizedBox(width: 12),
              Text('Report', style: TextStyle(color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// PROFILE HEADER
// ─────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Avatar with gradient border
          _GradientBorderAvatar(
            avatarUrl: profile.avatarUrl,
            isBestFriend: profile.isBestFriend,
            isCloseFriend: profile.isCloseFriend,
          ),
          const SizedBox(height: 16),
          // Display name with verified badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  profile.displayName,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (profile.isVerified) ...[
                const SizedBox(width: 8),
                const Icon(Icons.verified, size: 22, color: _kSnapchatBlue),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // Username
          Text(
            '@${profile.username}',
            style: const TextStyle(
              fontSize: 15,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          // Snap Score & University badges
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Snap Score badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('👻', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      _formatNumber(profile.snapScore),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              // University badge
              if (profile.university != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF6366F1).withValues(alpha: 0.15),
                        const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.school_rounded, size: 12, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              profile.university!.shortName,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6366F1),
                                letterSpacing: 0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Verified Student',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF6366F1).withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ).createShader(bounds),
                        child: const Icon(Icons.verified_rounded, size: 16, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatNumber(int num) {
    if (num >= 1000000) return '${(num / 1000000).toStringAsFixed(1)}M';
    if (num >= 1000) return '${(num / 1000).toStringAsFixed(num >= 10000 ? 0 : 1)}K';
    return num.toString();
  }
}

// ─────────────────────────────────────────────────────────────────
// GRADIENT BORDER AVATAR
// ─────────────────────────────────────────────────────────────────

class _GradientBorderAvatar extends StatelessWidget {
  final String? avatarUrl;
  final bool isBestFriend;
  final bool isCloseFriend;

  const _GradientBorderAvatar({
    this.avatarUrl,
    this.isBestFriend = false,
    this.isCloseFriend = false,
  });

  @override
  Widget build(BuildContext context) {
    final Gradient borderGradient;
    if (isBestFriend) {
      borderGradient = const LinearGradient(
        colors: [_kSnapchatYellow, _kSnapchatGold],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else if (isCloseFriend) {
      borderGradient = const LinearGradient(
        colors: [_kSnapchatBlue, Color(0xFF00C2FF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else {
      borderGradient = LinearGradient(
        colors: [Colors.grey[600]!, Colors.grey[700]!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }

    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: borderGradient,
      ),
      padding: const EdgeInsets.all(3),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.backgroundColor,
        ),
        padding: const EdgeInsets.all(3),
        child: avatarUrl != null && avatarUrl!.isNotEmpty
            ? ClipOval(
                child: CachedNetworkImage(
                  imageUrl: avatarUrl!,
                  width: 104,
                  height: 104,
                  fit: BoxFit.cover,
                  placeholder: (_, url) => _buildPlaceholder(),
                  errorWidget: (_, url, err) => _buildPlaceholder(),
                ),
              )
            : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.person, size: 52, color: Colors.grey[600]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// ACTION BUTTONS ROW
// ─────────────────────────────────────────────────────────────────

class _ActionButtonsRow extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onSendMessage;
  final VoidCallback onSendSnap;
  final VoidCallback onMore;

  const _ActionButtonsRow({
    required this.profile,
    required this.onSendMessage,
    required this.onSendSnap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final isAccepted = profile.friendshipStatus == FriendshipStatus.accepted;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          // Send Message - Primary
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: isAccepted ? onSendMessage : null,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: isAccepted ? _kSnapchatBlue : AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_rounded,
                      size: 20,
                      color: isAccepted ? Colors.white : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Message',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isAccepted ? Colors.white : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Send Snap - Outlined
          Expanded(
            child: GestureDetector(
              onTap: onSendSnap,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.surfaceColor, width: 2),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt_rounded, size: 20, color: AppTheme.textPrimary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // More Options
          GestureDetector(
            onTap: onMore,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.more_horiz, size: 22, color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// FRIENDSHIP INFO CARD
// ─────────────────────────────────────────────────────────────────

class _FriendshipInfoCard extends StatelessWidget {
  final UserProfile profile;
  const _FriendshipInfoCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    if (!profile.isBestFriend && !profile.isCloseFriend && profile.streakCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Friendship Level
          if (profile.isBestFriend || profile.isCloseFriend)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: profile.isBestFriend
                    ? _kSnapchatYellow.withValues(alpha: 0.15)
                    : _kSnapchatBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profile.isBestFriend ? '⭐' : '💛',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    profile.isBestFriend ? 'Best Friend' : 'Close Friend',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: profile.isBestFriend ? _kSnapchatYellow : _kSnapchatBlue,
                    ),
                  ),
                ],
              ),
            ),
          // Streak
          if (profile.streakCount > 0)
            Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Text(
                  '${profile.streakCount}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'day streak',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// MUTUAL FRIENDS CARD
// ─────────────────────────────────────────────────────────────────

class _MutualFriendsCard extends StatelessWidget {
  final List<FriendUser> mutualFriends;
  final Function(String) onTapFriend;

  const _MutualFriendsCard({
    required this.mutualFriends,
    required this.onTapFriend,
  });

  @override
  Widget build(BuildContext context) {
    final displayCount = mutualFriends.length > 6 ? 6 : mutualFriends.length;
    final remaining = mutualFriends.length - displayCount;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people, size: 18, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Text(
                '${mutualFriends.length} Mutual Friend${mutualFriends.length > 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 70,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: displayCount + (remaining > 0 ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= displayCount) {
                  // "+N more" indicator
                  return Container(
                    width: 56,
                    margin: const EdgeInsets.only(right: 12),
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceColor,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '+$remaining',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final friend = mutualFriends[index];
                return GestureDetector(
                  onTap: () => onTapFriend(friend.id),
                  child: Container(
                    width: 56,
                    margin: const EdgeInsets.only(right: 12),
                    child: Column(
                      children: [
                        AvatarWidget(avatarUrl: friend.avatarUrl, radius: 24),
                        const SizedBox(height: 6),
                        Text(
                          friend.displayName.split(' ').first,
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// SNAP MAP CARD
// ─────────────────────────────────────────────────────────────────

class _SnapMapCard extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onTapMap;

  const _SnapMapCard({required this.profile, required this.onTapMap});

  @override
  Widget build(BuildContext context) {
    final location = profile.location;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.location_on, size: 18, color: Colors.red[400]),
                const SizedBox(width: 8),
                const Text(
                  'Snap Map',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (location != null) ...[
            // Static map image
            GestureDetector(
              onTap: onTapMap,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                child: Stack(
                  children: [
                    CachedNetworkImage(
                      imageUrl:
                          'https://api.mapbox.com/styles/v1/mapbox/dark-v11/static/pin-s+ff0000(${location.longitude},${location.latitude})/${location.longitude},${location.latitude},13/400x180@2x?access_token=$_kMapboxToken',
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, url) => Container(
                        height: 180,
                        color: AppTheme.surfaceColor,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, url, err) => Container(
                        height: 180,
                        color: AppTheme.surfaceColor,
                        child: const Center(
                          child: Icon(Icons.map, size: 40, color: AppTheme.textMuted),
                        ),
                      ),
                    ),
                    // Location info overlay
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    location.area ?? 'Unknown Area',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  if (location.updatedAt != null)
                                    Text(
                                      'Updated ${timeago.format(location.updatedAt!)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[400],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Location not shared
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(Icons.location_off, size: 32, color: Colors.grey[600]),
                    const SizedBox(height: 12),
                    const Text(
                      'Location not shared',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "This friend hasn't shared their location with you",
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// SAVED IN CHAT CARD
// ─────────────────────────────────────────────────────────────────

class _SavedInChatCard extends StatelessWidget {
  const _SavedInChatCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bookmark, size: 18, color: AppTheme.textSecondary),
              SizedBox(width: 8),
              Text(
                'Saved in Chat',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 80,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bookmark_border, size: 28, color: Colors.grey[600]),
                const SizedBox(height: 8),
                Text(
                  'No saved messages',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// STORIES CARD
// ─────────────────────────────────────────────────────────────────

class _StoriesCard extends StatelessWidget {
  const _StoriesCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_stories, size: 18, color: AppTheme.textSecondary),
              SizedBox(width: 8),
              Text(
                'Stories',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 80,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_toggle_off, size: 28, color: Colors.grey[600]),
                const SizedBox(height: 8),
                Text(
                  'No recent stories',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// FRIENDSHIP ACTION BUTTON
// ─────────────────────────────────────────────────────────────────

class _FriendshipActionButton extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onAdd;
  final VoidCallback onUnblock;

  const _FriendshipActionButton({
    required this.profile,
    required this.onAdd,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    switch (profile.friendshipStatus) {
      case FriendshipStatus.pending:
        return SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: null,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
              side: const BorderSide(color: AppTheme.surfaceColor),
            ),
            child: Text(
              'Request Pending',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          ),
        );
      case FriendshipStatus.blocked:
        return SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onUnblock,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
            ),
            child: const Text(
              'Unblock',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        );
      default:
        return SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add, size: 20),
            label: const Text(
              'Add Friend',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kSnapchatYellow,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
            ),
          ),
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            const Text(
              'User not found',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'This user may have been deleted or does not exist.',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportReasonTile extends StatelessWidget {
  final String reason;
  final bool isSelected;
  final VoidCallback onTap;

  const _ReportReasonTile({
    required this.reason,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? AppTheme.primaryColor : AppTheme.textMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              reason,
              style: TextStyle(
                fontSize: 15,
                color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomSheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _BottomSheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppTheme.errorColor : AppTheme.textPrimary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }
}
