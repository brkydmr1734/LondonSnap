import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/features/auth/providers/auth_provider.dart';
import 'package:londonsnaps/features/social/providers/social_provider.dart';
import 'package:londonsnaps/features/stories/providers/stories_provider.dart';
import 'package:londonsnaps/features/memories/providers/memory_provider.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';
import 'package:londonsnaps/shared/widgets/notification_bell.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthProvider _authProvider = AuthProvider();
  final SocialProvider _socialProvider = SocialProvider();
  final StoriesProvider _storiesProvider = StoriesProvider();
  final MemoryProvider _memoryProvider = MemoryProvider();
  final ApiService _api = ApiService();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _authProvider.addListener(_onUpdate);
    _socialProvider.addListener(_onUpdate);
    _authProvider.checkAuthState();
    _socialProvider.loadFriends();
    _socialProvider.loadStreaks();
    _storiesProvider.loadMyStories();
    _memoryProvider.loadMemories();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onUpdate);
    _socialProvider.removeListener(_onUpdate);
    _bioController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _authProvider.currentUser;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.pop(context);
            } else {
              GoRouter.of(context).go('/chats');
            }
          },
        ),
        title: Text(user?.username != null ? '@${user!.username}' : 'Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code),
            onPressed: () => _showQRCode(),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
          const NotificationBell(),
        ],
      ),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _authProvider.checkAuthState();
                await _socialProvider.loadFriends();
                await _socialProvider.loadStreaks();
              },
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    // Profile picture
                    GestureDetector(
                      onTap: () => _showAvatarOptions(),
                      child: Stack(
                        children: [
                          Container(
                            width: 100, height: 100,
                            decoration: BoxDecoration(
                              gradient: _storiesProvider.myStories.isNotEmpty
                                  ? AppTheme.storyGradient : null,
                              border: _storiesProvider.myStories.isEmpty
                                  ? Border.all(color: AppTheme.surfaceColor, width: 3) : null,
                              shape: BoxShape.circle,
                            ),
                            padding: _storiesProvider.myStories.isNotEmpty
                                ? const EdgeInsets.all(3) : null,
                            child: AvatarWidget(
                              avatarUrl: user.avatarUrl,
                              radius: 47,
                            ),
                          ),
                          Positioned(
                            right: 0, bottom: 0,
                            child: Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.backgroundColor, width: 2),
                              ),
                              child: const Icon(Icons.edit, size: 16, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Name
                    Text(
                      user.displayName,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    // Username with lock icon
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '@${user.username}',
                          style: const TextStyle(color: AppTheme.textMuted),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.lock_outline,
                          size: 12,
                          color: AppTheme.textMuted,
                        ),
                      ],
                    ),
                    // Verified badge
                    if (user.isVerified) ...[
                      const SizedBox(height: 6),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.verified, size: 16, color: AppTheme.primaryColor),
                          SizedBox(width: 4),
                          Text('Verified',
                            style: TextStyle(fontSize: 12, color: AppTheme.primaryColor)),
                        ],
                      ),
                    ],
                    // Bio
                    if (user.bio != null && user.bio!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          user.bio!,
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // University verification CTA or badge
                    if (user.isUniversityStudent && user.university != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF6366F1).withValues(alpha: 0.15),
                              const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.school_rounded, size: 14, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    user.university!.shortName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF6366F1),
                                      letterSpacing: 0.3,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Verified Student',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFF6366F1).withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                              ).createShader(bounds),
                              child: const Icon(Icons.verified_rounded, size: 18, color: Colors.white),
                            ),
                          ],
                        ),
                      )
                    else if (!user.isUniversityStudent)
                      GestureDetector(
                        onTap: () => context.push('/university-verification'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.school, size: 16, color: Colors.white),
                              SizedBox(width: 6),
                              Text(
                                'Verify University',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white70),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    // Stats
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _StatItem(
                          value: '👻 ${_formatSnapScore(user.snapScore)}',
                          label: 'Snap Score',
                          onTap: () => _showEmojiLegend(),
                        ),
                        _StatItem(
                          value: '${_socialProvider.friends.length}',
                          label: 'Friends',
                          onTap: () => context.push('/friends'),
                        ),
                        _StatItem(
                          value: _socialProvider.streaks.isNotEmpty
                              ? '${_socialProvider.streaks.first.count} ${_socialProvider.streaks.first.emoji}'
                              : '0',
                          label: 'Best Streak',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Action buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                _displayNameController.text = user.displayName;
                                _bioController.text = user.bio ?? '';
                                _showEditProfile();
                              },
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(44),
                              ),
                              child: const Text('Edit Profile'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _shareProfile(),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(44),
                              ),
                              child: const Text('Share Profile'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // At-risk streaks
                    if (_socialProvider.atRiskStreaks.isNotEmpty) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.warningColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Text('⚠️', style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_socialProvider.atRiskStreaks.length} streak(s) expiring soon!',
                                style: const TextStyle(
                                  color: AppTheme.warningColor, fontWeight: FontWeight.w600),
                              ),
                            ),
                            TextButton(
                              onPressed: () => context.go('/chats'),
                              child: const Text('Send Snap'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Menu items
                    _MenuItem(
                      icon: Icons.people,
                      title: 'Friends',
                      subtitle: '${_socialProvider.friends.length} friends',
                      onTap: () => context.push('/friends'),
                    ),
                    _MenuItem(
                      icon: Icons.local_fire_department,
                      title: 'Streaks',
                      subtitle: '${_socialProvider.streaks.length} active',
                      onTap: () => context.push('/friends'),
                    ),
                    _MenuItem(
                      icon: Icons.person_add,
                      title: 'Add Friends',
                      subtitle: '${_socialProvider.suggestions.length} suggestions',
                      onTap: () => context.push('/friends'),
                    ),
                    _MenuItem(
                      icon: Icons.photo_library,
                      title: 'Memories',
                      subtitle: '${_memoryProvider.totalMemories} saved',
                      onTap: () => context.push('/memories'),
                    ),
                    _MenuItem(
                      icon: Icons.history,
                      title: 'My Story',
                      subtitle: '${_storiesProvider.myStories.length} stories',
                      onTap: () => context.go('/stories'),
                    ),
                    _MenuItem(
                      icon: Icons.bookmark,
                      title: 'Saved',
                      onTap: () => context.push('/saved-content'),
                    ),
                    _MenuItem(
                      icon: Icons.notifications,
                      title: 'Notifications',
                      onTap: () => _showNotificationSettings(),
                    ),
                    _MenuItem(
                      icon: Icons.privacy_tip,
                      title: 'Privacy',
                      onTap: () => context.push('/settings'),
                    ),
                    const Divider(height: 32),
                    _MenuItem(
                      icon: Icons.logout,
                      title: 'Log Out',
                      isDestructive: true,
                      onTap: () => _showLogoutDialog(),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
    );
  }

  void _showAvatarOptions() {
    // Show options to change profile photo
    _pickProfilePhoto();
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image == null) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uploading photo...')),
        );
      }

      // Upload to S3 via media endpoint
      final uploadRes = await _api.uploadMedia(image.path);
      final mediaUrl = uploadRes.data['data']?['media']?['url'] as String?;
      if (mediaUrl == null) throw Exception('Upload failed');

      // Set as avatar URL
      await _api.updateAvatarUrl(mediaUrl);
      await _authProvider.checkAuthState();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated!'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      String errorMessage = 'Upload failed';
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final responseData = e.response?.data;
        String? serverMsg;
        if (responseData is Map) {
          serverMsg = responseData['message'] as String? ?? responseData['error'] as String?;
        }
        if (serverMsg != null && serverMsg.isNotEmpty) {
          errorMessage = serverMsg;
        } else if (statusCode == 401) {
          errorMessage = 'Session expired. Please log in again';
        } else if (statusCode == 413) {
          errorMessage = 'Photo is too large';
        } else {
          errorMessage = 'Upload failed (error $statusCode)';
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  void _showQRCode() {
    final user = _authProvider.currentUser;
    if (user == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('My QR Code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: 'londonsnaps://profile/${user.username}',
                version: QrVersions.auto,
                size: 200,
              ),
            ),
            const SizedBox(height: 12),
            Text('@${user.username}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('Scan to add me on LondonSnaps',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: 'londonsnaps://profile/${user.username}'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied!')),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Copy Link'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _shareProfile() {
    final user = _authProvider.currentUser;
    if (user == null) return;
    Share.share(
      'Add me on LondonSnaps! @${user.username}\nhttps://londonsnaps.com/u/${user.username}',
    );
  }

  void _showNotificationSettings() {
    bool messages = true;
    bool stories = true;
    bool friendRequests = true;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Notification Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Messages'),
                  value: messages,
                  activeThumbColor: AppTheme.primaryColor,
                  onChanged: (v) => setSheetState(() => messages = v),
                ),
                SwitchListTile(
                  title: const Text('Story Updates'),
                  value: stories,
                  activeThumbColor: AppTheme.primaryColor,
                  onChanged: (v) => setSheetState(() => stories = v),
                ),
                SwitchListTile(
                  title: const Text('Friend Requests'),
                  value: friendRequests,
                  activeThumbColor: AppTheme.primaryColor,
                  onChanged: (v) => setSheetState(() => friendRequests = v),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Notification settings saved')),
                      );
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }

  void _showEditProfile() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Edit Profile',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () async {
                    final name = _displayNameController.text.trim();
                    final bio = _bioController.text.trim();
                    if (name.isNotEmpty) {
                      try {
                        await _api.updateProfile({
                          'displayName': name,
                          'bio': bio,
                        });
                        await _authProvider.checkAuthState();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Profile updated!'),
                                backgroundColor: AppTheme.successColor),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed: $e'),
                                backgroundColor: AppTheme.errorColor),
                          );
                        }
                      }
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _displayNameController,
              decoration: const InputDecoration(labelText: 'Display Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioController,
              decoration: const InputDecoration(labelText: 'Bio'),
              maxLines: 3,
              maxLength: 150,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _authProvider.logout();
              if (context.mounted) context.go('/welcome');
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  String _formatSnapScore(int score) {
    if (score >= 1000000) {
      return '${(score / 1000000).toStringAsFixed(1)}M';
    } else if (score >= 1000) {
      return '${(score / 1000).toStringAsFixed(1)}K';
    }
    return NumberFormat.decimalPattern().format(score);
  }

  void _showEmojiLegend() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text('Friend Emojis',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _EmojiLegendItem(emoji: '💛', label: '#1 Best Friend',
                    description: 'You are each other\'s #1 best friend'),
                _EmojiLegendItem(emoji: '❤️', label: 'BFF',
                    description: '#1 best friend for 2 weeks'),
                _EmojiLegendItem(emoji: '💕', label: 'Super BFF',
                    description: '#1 best friend for 2 months'),
                _EmojiLegendItem(emoji: '😊', label: 'Best Friends',
                    description: 'In each other\'s top 8 best friends'),
                _EmojiLegendItem(emoji: '😏', label: 'BFs',
                    description: 'One of your best friends'),
                _EmojiLegendItem(emoji: '🔥', label: 'Snap Streak',
                    description: 'Snapped each other within 24 hours'),
                _EmojiLegendItem(emoji: '⏳', label: 'Streak Expiring',
                    description: 'Your streak is about to end!'),
                _EmojiLegendItem(emoji: '👶', label: 'New Friend',
                    description: 'Recently became friends'),
                _EmojiLegendItem(emoji: '🌟', label: 'Super Star',
                    description: 'You\'ve been friends for a year'),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback? onTap;

  const _StatItem({required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const _MenuItem({
    required this.icon, required this.title, this.subtitle,
    required this.onTap, this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
        color: isDestructive ? AppTheme.errorColor : AppTheme.textSecondary),
      title: Text(title,
        style: TextStyle(color: isDestructive ? AppTheme.errorColor : null)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted))
          : null,
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
      onTap: onTap,
    );
  }
}

class _EmojiLegendItem extends StatelessWidget {
  final String emoji;
  final String label;
  final String description;

  const _EmojiLegendItem({
    required this.emoji,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(description,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
