import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/core/api/api_service.dart';

class SavedSnap {
  final String id;
  final String snapId;
  final DateTime savedAt;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final String mediaType;
  final String? caption;
  final SavedSnapSender sender;

  SavedSnap({
    required this.id,
    required this.snapId,
    required this.savedAt,
    this.mediaUrl,
    this.thumbnailUrl,
    required this.mediaType,
    this.caption,
    required this.sender,
  });

  factory SavedSnap.fromJson(Map<String, dynamic> json) {
    final snap = json['snap'] as Map<String, dynamic>;
    return SavedSnap(
      id: json['id'] as String,
      snapId: json['snapId'] as String,
      savedAt: DateTime.parse(json['savedAt'] as String),
      mediaUrl: snap['mediaUrl'] as String?,
      thumbnailUrl: snap['thumbnailUrl'] as String?,
      mediaType: snap['mediaType'] as String? ?? 'IMAGE',
      caption: snap['caption'] as String?,
      sender: SavedSnapSender.fromJson(snap['sender'] as Map<String, dynamic>),
    );
  }

  bool get isVideo => mediaType == 'VIDEO';
  String get displayUrl => thumbnailUrl ?? mediaUrl ?? '';
}

class SavedSnapSender {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  SavedSnapSender({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  factory SavedSnapSender.fromJson(Map<String, dynamic> json) {
    return SavedSnapSender(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

class SavedContentScreen extends StatefulWidget {
  const SavedContentScreen({super.key});

  @override
  State<SavedContentScreen> createState() => _SavedContentScreenState();
}

class _SavedContentScreenState extends State<SavedContentScreen> {
  final ApiService _api = ApiService();
  final ScrollController _scrollController = ScrollController();

  List<SavedSnap> _savedSnaps = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _total = 0;

  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loadSavedSnaps();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreSavedSnaps();
    }
  }

  Future<void> _loadSavedSnaps({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _savedSnaps = [];
        _hasMore = true;
      });
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _api.getSavedSnaps(limit: _pageSize, offset: 0);
      final data = response.data['data'];
      final savedSnapsJson = data['savedSnaps'] as List;

      setState(() {
        _savedSnaps = savedSnapsJson
            .map((json) => SavedSnap.fromJson(json as Map<String, dynamic>))
            .toList();
        _total = data['total'] as int? ?? 0;
        _hasMore = data['hasMore'] as bool? ?? false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load saved snaps';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreSavedSnaps() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final response = await _api.getSavedSnaps(
        limit: _pageSize,
        offset: _savedSnaps.length,
      );
      final data = response.data['data'];
      final savedSnapsJson = data['savedSnaps'] as List;

      setState(() {
        _savedSnaps.addAll(
          savedSnapsJson
              .map((json) => SavedSnap.fromJson(json as Map<String, dynamic>))
              .toList(),
        );
        _hasMore = data['hasMore'] as bool? ?? false;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _unsaveSnap(SavedSnap snap) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Unsave Snap?'),
        content: const Text(
          'This snap will be removed from your saved collection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Unsave'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _api.unsaveSnap(snap.snapId);
      setState(() {
        _savedSnaps.removeWhere((s) => s.id == snap.id);
        _total = _total > 0 ? _total - 1 : 0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Snap unsaved'),
            backgroundColor: AppTheme.surfaceColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to unsave snap'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Saved'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _savedSnaps.isEmpty) {
      return _buildLoadingSkeleton();
    }

    if (_error != null && _savedSnaps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.textMuted),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadSavedSnaps(refresh: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_savedSnaps.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => _loadSavedSnaps(refresh: true),
      color: AppTheme.primaryColor,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Stats header
          SliverToBoxAdapter(
            child: _buildStatsHeader(),
          ),
          // Grid
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.75,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildSnapTile(_savedSnaps[index]),
                childCount: _savedSnaps.length,
              ),
            ),
          ),
          // Loading more indicator
          if (_isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryColor),
                ),
              ),
            ),
          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 80),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        itemCount: 6,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.75,
        ),
        itemBuilder: (context, index) => Container(
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10,
                      width: 80,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                color: AppTheme.surfaceColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bookmark_outline,
                size: 48,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No saved snaps yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Save snaps to view them here.\nTap the bookmark icon on any snap to save it.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.go('/chats'),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('View Snaps'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bookmark, size: 16, color: AppTheme.primaryColor),
                const SizedBox(width: 6),
                Text(
                  '$_total saved',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapTile(SavedSnap snap) {
    return GestureDetector(
      onTap: () => _viewSnap(snap),
      onLongPress: () => _unsaveSnap(snap),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Media preview
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: snap.displayUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: AppTheme.surfaceColor,
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: AppTheme.surfaceColor,
                      child: const Icon(Icons.broken_image, color: AppTheme.textMuted),
                    ),
                  ),
                  // Video indicator
                  if (snap.isVideo)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.videocam,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  // Long press hint overlay
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.5),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Info section
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Caption or sender name
                  Text(
                    snap.caption?.isNotEmpty == true
                        ? snap.caption!
                        : 'From ${snap.sender.displayName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Save date
                  Row(
                    children: [
                      const Icon(
                        Icons.bookmark,
                        size: 12,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(snap.savedAt),
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return DateFormat('MMM d').format(date);
    }
  }

  void _viewSnap(SavedSnap snap) {
    // Show snap in a full-screen dialog
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background tap to dismiss
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(color: Colors.black87),
            ),
            // Snap content
            Center(
              child: CachedNetworkImage(
                imageUrl: snap.mediaUrl ?? snap.displayUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryColor),
                ),
                errorWidget: (context, url, error) => const Icon(
                  Icons.broken_image,
                  size: 64,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
            // Caption overlay
            if (snap.caption?.isNotEmpty == true)
              Positioned(
                bottom: 100,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    snap.caption!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            // Top bar
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Close button
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  // Sender info
                  Row(
                    children: [
                      Text(
                        snap.sender.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '@${snap.sender.username}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  // Unsave button
                  IconButton(
                    icon: const Icon(Icons.bookmark, color: AppTheme.primaryColor, size: 28),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _unsaveSnap(snap);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
