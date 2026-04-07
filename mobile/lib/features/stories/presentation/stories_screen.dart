import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/auth/providers/auth_provider.dart';
import 'package:londonsnaps/features/stories/models/story_models.dart';
import 'package:londonsnaps/features/stories/providers/stories_provider.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';
import 'package:londonsnaps/shared/widgets/notification_bell.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ── Helper: Download media bytes ──
Future<Uint8List?> _downloadMediaBytes(String url) async {
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode == 200) {
      final bytes = await response.fold<List<int>>([], (prev, element) => prev..addAll(element));
      return Uint8List.fromList(bytes);
    }
  } catch (_) {}
  return null;
}

// ── Snapchat Colors ──
class _SnapColors {
  static const Color background = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color viewedRing = Color(0xFF3A3A3C);
  static const Color addBadge = Color(0xFF0EADFF);
  static const Color inputBar = Color(0xFF1C1C1E);
  static const Color separator = Color(0xFF1C1C1E);

  static const List<Color> rainbowGradient = [
    Color(0xFFFF6B6B),
    Color(0xFFFFD93D),
    Color(0xFF6BCB77),
    Color(0xFF4D96FF),
    Color(0xFF9B59B6),
  ];

  static const LinearGradient storyRingGradient = LinearGradient(
    colors: rainbowGradient,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class StoriesScreen extends StatefulWidget {
  const StoriesScreen({super.key});

  @override
  State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  final StoriesProvider _storiesProvider = StoriesProvider();
  final AuthProvider _authProvider = AuthProvider();

  @override
  void initState() {
    super.initState();
    _storiesProvider.addListener(_onUpdate);
    _storiesProvider.loadStories();
    _storiesProvider.loadMyStories();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _storiesProvider.removeListener(_onUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: _SnapColors.background,
          body: SafeArea(
            child: _storiesProvider.isLoading && _storiesProvider.storyRings.isEmpty
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : RefreshIndicator(
                    color: _SnapColors.addBadge,
                    backgroundColor: _SnapColors.inputBar,
                    onRefresh: () async {
                      await _storiesProvider.loadStories();
                      await _storiesProvider.loadMyStories();
                    },
                    child: CustomScrollView(
                      slivers: [
                        // Custom Header
                        SliverToBoxAdapter(child: _buildHeader()),
                        // My Story Section
                        SliverToBoxAdapter(
                          child: _MyStorySection(
                            myStories: _storiesProvider.myStories,
                            currentUserAvatarUrl: _authProvider.currentUser?.avatarUrl,
                            onTap: () {
                              if (_storiesProvider.myStories.isNotEmpty) {
                                _storiesProvider.openStory(0);
                              }
                            },
                            onAdd: () => context.go('/camera'),
                            onMore: () => _showMyStoryOptions(),
                          ),
                        ),
                        // Friends Section
                        if (_storiesProvider.storyRings.isNotEmpty) ...[
                          SliverToBoxAdapter(child: _buildSectionHeader('Friends', onSeeAll: null)),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final ring = _storiesProvider.storyRings[index];
                                return _FriendStoryRow(
                                  ring: ring,
                                  onTap: () => _storiesProvider.openStory(index),
                                  onReply: () => _storiesProvider.openStory(index),
                                );
                              },
                              childCount: _storiesProvider.storyRings.length,
                            ),
                          ),
                        ] else
                          SliverToBoxAdapter(child: _buildEmptyFriendsState()),
                        // Discover Section
                        if (_storiesProvider.storyRings.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: _buildSectionHeader('Discover', onSeeAll: null),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            sliver: SliverGrid(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.7,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final ring = _storiesProvider.storyRings[index];
                                  return _DiscoverStoryCard(
                                    ring: ring,
                                    onTap: () => _storiesProvider.openStory(index),
                                  );
                                },
                                childCount: _storiesProvider.storyRings.length > 6
                                    ? 6
                                    : _storiesProvider.storyRings.length,
                              ),
                            ),
                          ),
                        ],
                        const SliverToBoxAdapter(child: SizedBox(height: 100)),
                      ],
                    ),
                  ),
          ),
        ),
        // Story Viewer overlay
        if (_storiesProvider.showStoryViewer)
          StoryViewerOverlay(provider: _storiesProvider),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Search icon
          GestureDetector(
            onTap: () {
              showSearch(
                context: context,
                delegate: _StorySearchDelegate(
                  storyRings: _storiesProvider.storyRings,
                  onSelect: (index) => _storiesProvider.openStory(index),
                ),
              );
            },
            child: const Icon(Icons.search, color: Colors.white, size: 26),
          ),
          const Spacer(),
          // Title
          const Text(
            'Stories',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // User avatar with yellow ring + NotificationBell
          Row(
            children: [
              const NotificationBell(),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => context.push('/profile'),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFFFC00), width: 2),
                  ),
                  child: AvatarWidget(
                    avatarUrl: _authProvider.currentUser?.avatarUrl,
                    radius: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: const Text(
                'See All',
                style: TextStyle(
                  color: _SnapColors.addBadge,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyFriendsState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 64, color: _SnapColors.textSecondary),
          const SizedBox(height: 16),
          const Text(
            'No Stories',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Stories from friends will show here',
            style: TextStyle(color: _SnapColors.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showMyStoryOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _SnapColors.inputBar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                color: _SnapColors.textSecondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.white),
              title: const Text('Story Settings', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showStorySettings();
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt, color: Colors.white),
              title: const Text('Save Story', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                if (_storiesProvider.myStories.isNotEmpty) {
                  _saveStoryToGallery(_storiesProvider.myStories.first);
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showStorySettings() {
    // Initialize with current story settings if available
    final currentStories = _storiesProvider.myStories;
    StoryPrivacy selectedPrivacy = currentStories.isNotEmpty
        ? currentStories.first.privacy
        : StoryPrivacy.friends;
    bool allowReplies = currentStories.isNotEmpty
        ? currentStories.first.allowReplies
        : true;
    // Capture parent scaffold messenger before entering the bottom sheet
    final parentMessenger = ScaffoldMessenger.of(context);
    final provider = _storiesProvider;

    showModalBottomSheet(
      context: context,
      backgroundColor: _SnapColors.inputBar,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: _SnapColors.textSecondary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Story Settings',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                const Text('Who can see my story?',
                  style: TextStyle(color: _SnapColors.textSecondary, fontSize: 14)),
                const SizedBox(height: 12),
                ...StoryPrivacy.values.where((p) => p != StoryPrivacy.custom).map((privacy) {
                  return GestureDetector(
                    onTap: () => setSheetState(() => selectedPrivacy = privacy),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: selectedPrivacy == privacy
                            ? _SnapColors.addBadge.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedPrivacy == privacy
                              ? _SnapColors.addBadge : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(privacy.icon, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(privacy.displayName,
                              style: const TextStyle(color: Colors.white, fontSize: 16)),
                          ),
                          if (selectedPrivacy == privacy)
                            const Icon(Icons.check_circle, color: _SnapColors.addBadge, size: 22),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Allow Replies',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                    Switch.adaptive(
                      value: allowReplies,
                      onChanged: (v) => setSheetState(() => allowReplies = v),
                      activeTrackColor: _SnapColors.addBadge,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      HapticFeedback.mediumImpact();
                      // Snapshot the stories list before async gap
                      final storiesToUpdate = List<Story>.from(provider.myStories);
                      if (storiesToUpdate.isEmpty) {
                        parentMessenger.showSnackBar(
                          const SnackBar(
                            content: Text('No active stories to update'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }
                      bool allSuccess = true;
                      String? lastError;
                      for (final story in storiesToUpdate) {
                        final ok = await provider.updateStorySettings(
                          story.id,
                          privacy: selectedPrivacy.value,
                          allowReplies: allowReplies,
                        );
                        if (!ok) {
                          allSuccess = false;
                          lastError = provider.error;
                        }
                      }
                      // Reload stories once after all updates
                      await provider.loadMyStories();
                      await provider.loadStories();
                      parentMessenger.showSnackBar(
                        SnackBar(
                          content: Text(allSuccess
                              ? 'Story privacy set to ${selectedPrivacy.displayName}'
                              : 'Failed to save: ${lastError ?? "Unknown error"}'),
                          backgroundColor: allSuccess ? AppTheme.successColor : Colors.red,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _SnapColors.addBadge,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Save Settings',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveStoryToGallery(Story story) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saving...'), duration: Duration(seconds: 1)),
      );
      final bytes = await _downloadMediaBytes(story.mediaUrl);
      if (bytes != null) {
        final result = await ImageGallerySaver.saveImage(
          bytes,
          quality: 100,
          name: 'story_${DateTime.now().millisecondsSinceEpoch}',
        );
        if (mounted) {
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['isSuccess'] == true ? 'Saved to gallery!' : 'Failed to save'),
              backgroundColor: result['isSuccess'] == true ? AppTheme.successColor : AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }
}

// ── My Story Section ──
class _MyStorySection extends StatelessWidget {
  final List<Story> myStories;
  final String? currentUserAvatarUrl;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final VoidCallback onMore;

  const _MyStorySection({
    required this.myStories,
    this.currentUserAvatarUrl,
    required this.onTap,
    required this.onAdd,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final avatarUrl = myStories.isNotEmpty
        ? myStories.first.user.avatarUrl
        : currentUserAvatarUrl;

    final hasStories = myStories.isNotEmpty;
    final storyTime = hasStories ? myStories.first.formattedTime : null;

    return GestureDetector(
      onTap: hasStories ? onTap : onAdd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: _SnapColors.background,
        child: Row(
          children: [
            // Avatar with ring and + badge
            Stack(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: hasStories ? _SnapColors.storyRingGradient : null,
                    border: !hasStories
                        ? Border.all(
                            color: _SnapColors.textSecondary,
                            width: 2,
                            strokeAlign: BorderSide.strokeAlignInside,
                          )
                        : null,
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: _SnapColors.background,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: AvatarWidget(avatarUrl: avatarUrl, radius: 25),
                  ),
                ),
                // + Badge (always visible)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: onAdd,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _SnapColors.addBadge,
                        shape: BoxShape.circle,
                        border: Border.all(color: _SnapColors.background, width: 2),
                      ),
                      child: const Icon(Icons.add, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // Text column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Story',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasStories
                        ? '${myStories.length} ${myStories.length == 1 ? 'story' : 'stories'} • $storyTime'
                        : 'Add to my story',
                    style: const TextStyle(
                      color: _SnapColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            // Three-dot menu
            GestureDetector(
              onTap: onMore,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.more_horiz, color: Colors.white, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Friend Story Row (Vertical List Item) ──
class _FriendStoryRow extends StatelessWidget {
  final StoryRing ring;
  final VoidCallback onTap;
  final VoidCallback onReply;

  const _FriendStoryRow({
    required this.ring,
    required this.onTap,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final storyCount = ring.stories.length;
    final latestTime = ring.latestStory?.formattedTime ?? '';
    final subtitle = storyCount > 1 ? '$latestTime • $storyCount stories' : latestTime;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: _SnapColors.background,
          border: Border(
            bottom: BorderSide(color: _SnapColors.separator, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Avatar with ring
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ring.hasUnviewed ? _SnapColors.storyRingGradient : null,
                color: ring.hasUnviewed ? null : _SnapColors.viewedRing,
              ),
              padding: const EdgeInsets.all(2.5),
              child: Container(
                decoration: const BoxDecoration(
                  color: _SnapColors.background,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: AvatarWidget(avatarUrl: ring.user.avatarUrl, radius: 21),
              ),
            ),
            const SizedBox(width: 12),
            // Name + time column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ring.user.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _SnapColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            // Camera/snap reply shortcut
            GestureDetector(
              onTap: onReply,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.camera_alt_outlined,
                  color: _SnapColors.textSecondary,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Discover Story Card ──
class _DiscoverStoryCard extends StatelessWidget {
  final StoryRing ring;
  final VoidCallback onTap;

  const _DiscoverStoryCard({required this.ring, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final story = ring.latestStory;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _SnapColors.inputBar,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail
            if (story?.thumbnailUrl != null)
              CachedNetworkImage(
                imageUrl: story!.thumbnailUrl!,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: _SnapColors.inputBar),
                errorWidget: (_, _, _) => Container(
                  color: _SnapColors.inputBar,
                  child: const Icon(Icons.image, color: _SnapColors.textSecondary),
                ),
              )
            else
              Container(
                decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
              ),
            // Bottom gradient overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 80,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.9),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // User info overlay
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AvatarWidget(avatarUrl: ring.user.avatarUrl, radius: 12),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ring.user.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (story != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.remove_red_eye, size: 12, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          '${story.viewCount}',
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Story Viewer Overlay ──
class StoryViewerOverlay extends StatefulWidget {
  final StoriesProvider provider;
  const StoryViewerOverlay({super.key, required this.provider});

  @override
  State<StoryViewerOverlay> createState() => _StoryViewerOverlayState();
}

class _StoryViewerOverlayState extends State<StoryViewerOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  final TextEditingController _replyController = TextEditingController();
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    widget.provider.addListener(_onProviderUpdate);
    _replyController.addListener(() {
      if (mounted) setState(() {});
    });
    _progressController = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.provider.currentStory?.duration ?? 5),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (!widget.provider.nextStory()) {
            widget.provider.closeViewer();
          } else {
            _startProgress();
          }
        }
      });
    _startProgress();
    _markViewed();
  }

  void _onProviderUpdate() {
    if (mounted) setState(() {});
  }

  void _startProgress() {
    final story = widget.provider.currentStory;
    if (story == null) return;
    _progressController.duration = Duration(seconds: story.duration);
    _progressController.forward(from: 0);
    _markViewed();
  }

  void _markViewed() {
    final story = widget.provider.currentStory;
    if (story != null) widget.provider.viewStory(story);
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onProviderUpdate);
    _progressController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  void _showStoryOptions(Story story) {
    _progressController.stop();
    final isOwnStory = story.userId == AuthProvider().currentUser?.id;

    showModalBottomSheet(
      context: context,
      backgroundColor: _SnapColors.inputBar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                color: _SnapColors.textSecondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            if (isOwnStory) ...[
              ListTile(
                leading: const Icon(Icons.delete, color: AppTheme.errorColor),
                title: const Text('Delete Story',
                    style: TextStyle(color: AppTheme.errorColor)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.provider.deleteStory(story.id);
                  widget.provider.closeViewer();
                },
              ),
              ListTile(
                leading: const Icon(Icons.save_alt, color: Colors.white),
                title: const Text('Save Story', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveStoryMedia(story);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.white),
                title: const Text('Share', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareStoryMedia(story);
                },
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.white),
                title: const Text('Report', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _progressController.forward();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Story reported. Thank you.')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.volume_off, color: Colors.white),
                title: const Text('Mute User', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _progressController.forward();
                  HapticFeedback.mediumImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${story.user.displayName} muted'),
                      backgroundColor: AppTheme.successColor,
                      action: SnackBarAction(
                        label: 'Undo',
                        textColor: Colors.white,
                        onPressed: () {},
                      ),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    ).whenComplete(() {
      if (mounted && !_isPaused) _progressController.forward();
    });
  }
  
  Future<void> _saveStoryMedia(Story story) async {
    try {
      _progressController.stop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saving...'), duration: Duration(seconds: 1)),
      );
      final bytes = await _downloadMediaBytes(story.mediaUrl);
      if (bytes != null) {
        final result = await ImageGallerySaver.saveImage(
          bytes,
          quality: 100,
          name: 'story_${DateTime.now().millisecondsSinceEpoch}',
        );
        if (mounted) {
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['isSuccess'] == true ? 'Saved to gallery!' : 'Failed to save'),
              backgroundColor: result['isSuccess'] == true ? AppTheme.successColor : AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
    if (mounted && !_isPaused) _progressController.forward();
  }
  
  Future<void> _shareStoryMedia(Story story) async {
    try {
      _progressController.stop();
      final bytes = await _downloadMediaBytes(story.mediaUrl);
      if (bytes != null) {
        final tempDir = await getTemporaryDirectory();
        final ext = story.mediaType == StoryMediaType.video ? 'mp4' : 'jpg';
        final file = File('${tempDir.path}/share_story.$ext');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles(
          [XFile(file.path)],
          text: story.caption ?? 'Check out my story on LondonSnap!',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
    if (mounted && !_isPaused) _progressController.forward();
  }
  
  void _onTapLeft() {
    if (!widget.provider.previousStory()) {
      widget.provider.closeViewer();
    } else {
      _startProgress();
    }
  }

  void _onTapRight() {
    if (!widget.provider.nextStory()) {
      widget.provider.closeViewer();
    } else {
      _startProgress();
    }
  }

  void _onLongPressStart() {
    _isPaused = true;
    _progressController.stop();
  }

  void _onLongPressEnd() {
    _isPaused = false;
    _progressController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.provider.currentStory;
    final ring = widget.provider.currentStoryRing;
    if (story == null || ring == null) return const SizedBox();

    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: _SnapColors.background,
        child: SafeArea(
          child: Stack(
            children: [
              // Story content (full screen)
              Positioned.fill(
                child: story.mediaType == StoryMediaType.image && story.mediaUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: story.mediaUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          color: _SnapColors.background,
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                        errorWidget: (_, _, _) => Container(
                          color: _SnapColors.inputBar,
                          child: const Center(
                            child: Icon(Icons.error, color: Colors.white54, size: 48),
                          ),
                        ),
                      )
                    : Container(
                        decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              story.caption ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
              ),
              // Caption overlay (for images with caption)
              if (story.caption != null && story.mediaType == StoryMediaType.image)
                Positioned(
                  bottom: story.allowReplies ? 100 : 40,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Text(
                      story.caption!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              // Location badge
              if (story.location != null)
                Positioned(
                  top: 90,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('📍', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Text(
                            story.location!.name,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Tap zones (left 1/3, right 2/3)
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: GestureDetector(
                      onTap: _onTapLeft,
                      onLongPressStart: (_) => _onLongPressStart(),
                      onLongPressEnd: (_) => _onLongPressEnd(),
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _onTapRight,
                      onLongPressStart: (_) => _onLongPressStart(),
                      onLongPressEnd: (_) => _onLongPressEnd(),
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
              // Top gradient for progress bars
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 100,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Progress bars & header
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    // Progress bars
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        children: List.generate(ring.stories.length, (i) {
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 1.5),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(1.5),
                                child: SizedBox(
                                  height: 3,
                                  child: i < widget.provider.currentStoryIndex
                                      ? Container(color: Colors.white)
                                      : i == widget.provider.currentStoryIndex
                                          ? _AnimatedProgressBar(controller: _progressController)
                                          : Container(color: Colors.white30),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    // User info row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          AvatarWidget(avatarUrl: ring.user.avatarUrl, radius: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    ring.user.displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (ring.user.isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified, size: 14, color: _SnapColors.addBadge),
                                ],
                                const SizedBox(width: 8),
                                Text(
                                  story.formattedTime,
                                  style: const TextStyle(
                                    color: _SnapColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _showStoryOptions(story),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.more_horiz, color: Colors.white, size: 24),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => widget.provider.closeViewer(),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.close, color: Colors.white, size: 24),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Reply input (bottom) - only for other people's stories
              if (story.allowReplies && story.userId != AuthProvider().currentUser?.id)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.only(
                      left: 12,
                      right: 12,
                      top: 12,
                      bottom: MediaQuery.of(context).padding.bottom + 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.9),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        // Camera icon
                        GestureDetector(
                          onTap: () {
                            widget.provider.closeViewer();
                            context.go('/camera');
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: _SnapColors.inputBar,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Text input
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: _SnapColors.inputBar,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _replyController,
                                    decoration: const InputDecoration(
                                      hintText: 'Send a chat',
                                      hintStyle: TextStyle(color: _SnapColors.textSecondary),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    style: const TextStyle(color: Colors.white, fontSize: 15),
                                    onTap: () => _progressController.stop(),
                                    onSubmitted: (text) {
                                      if (text.isNotEmpty) {
                                        widget.provider.replyToStory(story.id, content: text);
                                        _replyController.clear();
                                      }
                                      _progressController.forward();
                                    },
                                  ),
                                ),
                                if (_replyController.text.isNotEmpty)
                                  GestureDetector(
                                    onTap: () {
                                      if (_replyController.text.isNotEmpty) {
                                        widget.provider.replyToStory(
                                          story.id,
                                          content: _replyController.text,
                                        );
                                        _replyController.clear();
                                        _progressController.forward();
                                      }
                                    },
                                    child: const Icon(
                                      Icons.send,
                                      color: _SnapColors.addBadge,
                                      size: 20,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Quick emoji reactions
                        ...['\u2764\uFE0F', '\uD83D\uDE02', '\uD83D\uDE2E'].map(
                          (emoji) => GestureDetector(
                            onTap: () {
                              widget.provider.reactToStory(story.id, emoji);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: _SnapColors.inputBar,
                                shape: BoxShape.circle,
                              ),
                              child: Text(emoji, style: const TextStyle(fontSize: 18)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper widget for animated progress ──
class _AnimatedProgressBar extends StatelessWidget {
  final AnimationController controller;
  const _AnimatedProgressBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) => Stack(
        children: [
          Container(color: Colors.white30),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: controller.value,
            child: Container(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  const AnimatedBuilder({super.key, required Animation<double> animation, required this.builder})
      : super(listenable: animation);

  @override
  Widget build(BuildContext context) => builder(context, null);
}

// ── Story Search Delegate ──
class _StorySearchDelegate extends SearchDelegate<void> {
  final List<StoryRing> storyRings;
  final Function(int) onSelect;

  _StorySearchDelegate({required this.storyRings, required this.onSelect});

  @override
  String get searchFieldLabel => 'Search stories...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Color(0xFF8E8E93)),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear, color: Colors.white),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.white),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    final filtered = query.isEmpty
        ? storyRings
        : storyRings.where((r) =>
            r.user.displayName.toLowerCase().contains(query.toLowerCase()) ||
            r.user.username.toLowerCase().contains(query.toLowerCase())
          ).toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text('No stories found', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16)),
      );
    }

    return Container(
      color: Colors.black,
      child: ListView.builder(
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final ring = filtered[index];
          final originalIndex = storyRings.indexOf(ring);
          return ListTile(
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ring.hasUnviewed
                    ? const LinearGradient(
                        colors: [Color(0xFFFF6B6B), Color(0xFFFFD93D), Color(0xFF6BCB77), Color(0xFF4D96FF)],
                      )
                    : null,
                color: ring.hasUnviewed ? null : const Color(0xFF3A3A3C),
              ),
              padding: const EdgeInsets.all(2),
              child: Container(
                decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                padding: const EdgeInsets.all(1.5),
                child: AvatarWidget(avatarUrl: ring.user.avatarUrl, radius: 18),
              ),
            ),
            title: Text(ring.user.displayName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${ring.stories.length} ${ring.stories.length == 1 ? 'story' : 'stories'}',
              style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
            ),
            trailing: ring.hasUnviewed
                ? Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0EADFF),
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
            onTap: () {
              close(context, null);
              onSelect(originalIndex);
            },
          );
        },
      ),
    );
  }
}
