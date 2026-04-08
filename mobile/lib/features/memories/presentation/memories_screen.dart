import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/memories/models/memory_models.dart';
import 'package:londonsnaps/features/memories/providers/memory_provider.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/core/errors/app_exceptions.dart';
import 'package:londonsnaps/core/errors/error_handler.dart';

// Snapchat yellow color
const Color _snapYellow = Color(0xFFFFFC00);

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen>
    with SingleTickerProviderStateMixin {
  final MemoryProvider _memoryProvider = MemoryProvider();
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _memoryProvider.addListener(_onUpdate);
    _memoryProvider.loadMemories();
    _memoryProvider.checkVaultStatus();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _memoryProvider.removeListener(_onUpdate);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _SnapsTab(memoryProvider: _memoryProvider),
                  const _CameraRollTab(),
                  _MyEyesOnlyTab(memoryProvider: _memoryProvider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 22),
            onPressed: () => context.pop(),
          ),
          const Expanded(
            child: Text(
              'Memories',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 22),
            onPressed: _showSettingsSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: Colors.grey[500], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Search memories',
                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 15),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: TabBar(
        controller: _tabController,
        indicatorColor: _snapYellow,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey[500],
        labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Snaps'),
          Tab(text: 'Camera Roll'),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, size: 14),
                SizedBox(width: 4),
                Text('My Eyes Only'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsSheet() {
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
            ListTile(
              leading: const Icon(Icons.photo_album_outlined, color: Colors.white),
              title: const Text('Albums', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showAlbumsSheet();
              },
            ),
            if (_memoryProvider.hasVault)
              ListTile(
                leading: const Icon(Icons.lock_reset, color: Colors.white),
                title: const Text('Change Passcode', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  // TODO: Implement change passcode flow
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showAlbumsSheet() {
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
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Albums',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.surfaceColor),
            if (_memoryProvider.albums.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No albums yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted),
                ),
              )
            else
              ..._memoryProvider.albums.map((album) => ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(8),
                        image: album.coverUrl != null
                            ? DecorationImage(
                                image: CachedNetworkImageProvider(album.coverUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: album.coverUrl == null
                          ? const Icon(Icons.folder, color: _snapYellow)
                          : null,
                    ),
                    title:
                        Text(album.name, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      '${album.memoryCount} memories',
                      style:
                          const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    onTap: () => Navigator.pop(ctx),
                  )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SNAPS TAB
// ═══════════════════════════════════════════════════════════════════════════

class _SnapsTab extends StatefulWidget {
  final MemoryProvider memoryProvider;

  const _SnapsTab({required this.memoryProvider});

  @override
  State<_SnapsTab> createState() => _SnapsTabState();
}

class _SnapsTabState extends State<_SnapsTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      widget.memoryProvider.loadMoreMemories();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Map<String, List<Memory>> get _memoriesByMonth {
    final grouped = <String, List<Memory>>{};
    for (final memory in widget.memoryProvider.memories) {
      if (!memory.isMyEyesOnly) {
        final key = _formatMonthYear(memory.takenAt);
        grouped.putIfAbsent(key, () => []).add(memory);
      }
    }
    return grouped;
  }

  String _formatMonthYear(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.memoryProvider.isLoading &&
        widget.memoryProvider.memories.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: _snapYellow),
      );
    }

    if (widget.memoryProvider.memories.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => widget.memoryProvider.loadMemories(refresh: true),
      color: _snapYellow,
      backgroundColor: AppTheme.cardColor,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Stats header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '${widget.memoryProvider.totalMemories} Snaps',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // Grouped memories
          ..._buildGroupedMemories(),
          // Loading more indicator
          if (widget.memoryProvider.isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(color: _snapYellow),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
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
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                size: 48,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No memories yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your saved snaps will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroupedMemories() {
    final grouped = _memoriesByMonth;
    final widgets = <Widget>[];

    for (final entry in grouped.entries) {
      // Section header
      widgets.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            entry.key,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ));

      // Grid
      widgets.add(SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _MemoryTile(
              memory: entry.value[index],
              onLongPress: () => _showMemoryOptions(entry.value[index]),
            ),
            childCount: entry.value.length,
          ),
        ),
      ));
    }

    return widgets;
  }

  void _showMemoryOptions(Memory memory) {
    HapticFeedback.mediumImpact();
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
            ListTile(
              leading: const Icon(Icons.lock_outline, color: _snapYellow),
              title: const Text('Move to My Eyes Only',
                  style: TextStyle(color: Colors.white)),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                final success = await widget.memoryProvider.moveToVault(memory.id);
                if (success) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Moved to My Eyes Only'),
                      backgroundColor: AppTheme.successColor,
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined, color: Colors.white),
              title: const Text('Share', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                // TODO: Share
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
              title: const Text('Delete',
                  style: TextStyle(color: AppTheme.errorColor)),
              onTap: () async {
                Navigator.pop(ctx);
                _confirmDelete(memory);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(Memory memory) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Delete Memory?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.memoryProvider.deleteMemory(memory.id);
            },
            child: const Text('Delete', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
  }
}

// Memory tile widget
class _MemoryTile extends StatelessWidget {
  final Memory memory;
  final VoidCallback onLongPress;
  final VoidCallback? onTap;

  const _MemoryTile({required this.memory, required this.onLongPress, this.onTap});

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = memory.thumbnailUrl ?? memory.mediaUrl;

    return GestureDetector(
      onTap: onTap ?? () => context.push('/memories/${memory.id}'),
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image
          CachedNetworkImage(
            imageUrl: thumbnailUrl,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 200),
            placeholder: (context, url) => Container(
              color: AppTheme.surfaceColor,
            ),
            errorWidget: (context, url, error) => Container(
              color: AppTheme.surfaceColor,
              child: const Icon(Icons.broken_image, color: AppTheme.textMuted),
            ),
          ),

          // Video duration badge
          if (memory.isVideo)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '0:00',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          // On This Day badge
          if (memory.isOnThisDay)
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _snapYellow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '📸',
                  style: TextStyle(fontSize: 10),
                ),
              ),
            ),

          // Caption overlay
          if (memory.caption != null && memory.caption!.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: Text(
                  memory.caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CAMERA ROLL TAB
// ═══════════════════════════════════════════════════════════════════════════

class _CameraRollTab extends StatefulWidget {
  const _CameraRollTab();

  @override
  State<_CameraRollTab> createState() => _CameraRollTabState();
}

class _CameraRollTabState extends State<_CameraRollTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  List<AssetEntity> _assets = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasPermission = false;
  bool _hasMore = true;
  int _currentPage = 0;
  static const int _pageSize = 50;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _requestPermissionAndLoad();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreAssets();
    }
  }

  Future<void> _requestPermissionAndLoad() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (permission.isAuth || permission.hasAccess) {
      setState(() => _hasPermission = true);
      await _loadAssets();
    } else {
      setState(() {
        _hasPermission = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAssets() async {
    if (!_hasPermission) return;

    setState(() => _isLoading = true);

    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
      );

      if (albums.isNotEmpty) {
        final recent = albums.first;
        final assets = await recent.getAssetListPaged(page: 0, size: _pageSize);
        final total = await recent.assetCountAsync;

        setState(() {
          _assets = assets;
          _currentPage = 0;
          _hasMore = assets.length < total;
          _isLoading = false;
        });
      } else {
        setState(() {
          _assets = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreAssets() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
      );

      if (albums.isNotEmpty) {
        final recent = albums.first;
        final nextPage = _currentPage + 1;
        final newAssets =
            await recent.getAssetListPaged(page: nextPage, size: _pageSize);
        final total = await recent.assetCountAsync;

        setState(() {
          _assets.addAll(newAssets);
          _currentPage = nextPage;
          _hasMore = _assets.length < total;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _snapYellow),
      );
    }

    if (!_hasPermission) {
      return _buildPermissionRequest();
    }

    if (_assets.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadAssets,
      color: _snapYellow,
      backgroundColor: AppTheme.cardColor,
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(2),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: _assets.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _assets.length) {
            return Container(
              color: AppTheme.surfaceColor,
              child: const Center(
                child: CircularProgressIndicator(
                  color: _snapYellow,
                  strokeWidth: 2,
                ),
              ),
            );
          }
          return _AssetTile(
            asset: _assets[index],
            onTap: () => _openAssetDetail(_assets[index]),
            onLongPress: () => _showAssetOptions(_assets[index]),
          );
        },
      ),
    );
  }

  Widget _buildPermissionRequest() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                size: 48,
                color: _snapYellow,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Allow Photo Access',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Access your photos to save and share your memories.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                await PhotoManager.openSetting();
                // Reload immediately when user returns (no artificial delay)
                _requestPermissionAndLoad();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _snapYellow,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
              child: const Text(
                'Allow Access',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        'No photos found',
        style: TextStyle(color: AppTheme.textMuted),
      ),
    );
  }

  void _openAssetDetail(AssetEntity asset) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _CameraRollDetailScreen(asset: asset),
      ),
    );
    // If photo was deleted, refresh the list
    if (result == true && mounted) {
      _loadAssets();
    }
  }

  void _showAssetOptions(AssetEntity asset) {
    HapticFeedback.mediumImpact();
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
            ListTile(
              leading: const Icon(Icons.save_alt, color: _snapYellow),
              title: const Text('Save to Memories',
                  style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(ctx);
                // TODO: Implement save to memories
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Saving to memories...'),
                      backgroundColor: AppTheme.cardColor,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  final AssetEntity asset;
  final VoidCallback onLongPress;
  final VoidCallback? onTap;

  const _AssetTile({required this.asset, required this.onLongPress, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(
              const ThumbnailSize(300, 300),
              quality: 80,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done &&
                  snapshot.data != null) {
                return Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                );
              }
              return Container(color: AppTheme.surfaceColor);
            },
          ),
          // Video duration
          if (asset.type == AssetType.video)
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatDuration(asset.duration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MY EYES ONLY TAB
// ═══════════════════════════════════════════════════════════════════════════

class _MyEyesOnlyTab extends StatefulWidget {
  final MemoryProvider memoryProvider;

  const _MyEyesOnlyTab({required this.memoryProvider});

  @override
  State<_MyEyesOnlyTab> createState() => _MyEyesOnlyTabState();
}

class _MyEyesOnlyTabState extends State<_MyEyesOnlyTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final provider = widget.memoryProvider;

    // Not setup
    if (!provider.hasVault) {
      return _VaultSetupView(
        onSetup: (pin) async {
          final success = await provider.setupVault(pin);
          if (!success) return false;
          if (mounted) {
            return await provider.unlockVault(pin);
          }
          return false;
        },
        errorText: provider.vaultError,
      );
    }

    // Locked
    if (!provider.isVaultUnlocked) {
      return _PinEntryView(
        onUnlock: (pin) async {
          final success = await provider.unlockVault(pin);
          return success;
        },
        errorText: provider.vaultError,
      );
    }

    // Unlocked - show vault memories
    return _VaultMemoriesView(memoryProvider: provider);
  }
}

// ── Vault Setup View ──

class _VaultSetupView extends StatefulWidget {
  final Future<bool> Function(String pin) onSetup;
  final String? errorText;

  const _VaultSetupView({required this.onSetup, this.errorText});

  @override
  State<_VaultSetupView> createState() => _VaultSetupViewState();
}

class _VaultSetupViewState extends State<_VaultSetupView> {
  bool _isSettingUp = false;
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  String? _error;

  void _onDigit(int digit) {
    if (_isSettingUp) return;
    HapticFeedback.lightImpact();
    setState(() {
      _error = null;
      if (!_isConfirming) {
        if (_pin.length < 4) {
          _pin += digit.toString();
        }
        if (_pin.length == 4) {
          // Transition immediately, no artificial delay
          _isConfirming = true;
        }
      } else {
        if (_confirmPin.length < 4) {
          _confirmPin += digit.toString();
        }
        if (_confirmPin.length == 4) {
          _verifyAndSetup();
        }
      }
    });
  }

  void _onBackspace() {
    if (_isSettingUp) return;
    HapticFeedback.lightImpact();
    setState(() {
      if (!_isConfirming) {
        if (_pin.isNotEmpty) {
          _pin = _pin.substring(0, _pin.length - 1);
        }
      } else {
        if (_confirmPin.isNotEmpty) {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        }
      }
      _error = null;
    });
  }

  Future<void> _verifyAndSetup() async {
    if (_pin != _confirmPin) {
      setState(() {
        _error = 'PINs don\'t match. Try again.';
        _confirmPin = '';
      });
      HapticFeedback.heavyImpact();
      return;
    }

    setState(() {
      _isSettingUp = true;
      _error = null;
    });
    final success = await widget.onSetup(_pin);
    if (mounted) {
      setState(() {
        _isSettingUp = false;
        if (!success) {
          _error = widget.errorText ?? 'Failed to set up vault. Please try again.';
          _pin = '';
          _confirmPin = '';
          _isConfirming = false;
        }
      });
      if (!success) HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPin = _isConfirming ? _confirmPin : _pin;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 64, color: _snapYellow),
          const SizedBox(height: 24),
          Text(
            _isConfirming ? 'Confirm Passcode' : 'Set up My Eyes Only',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isConfirming
                ? 'Enter your passcode again'
                : 'Create a 4-digit passcode to protect your private memories',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 32),
          // PIN dots
          _PinDots(filledCount: currentPin.length, hasError: _error != null),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.errorColor, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 32),
          // Number pad
          if (_isSettingUp)
            const CircularProgressIndicator(color: _snapYellow)
          else
            _NumberPad(onDigit: _onDigit, onBackspace: _onBackspace),
        ],
      ),
    );
  }
}

// ── PIN Entry View ──

class _PinEntryView extends StatefulWidget {
  final Future<bool> Function(String pin) onUnlock;
  final String? errorText;

  const _PinEntryView({required this.onUnlock, this.errorText});

  @override
  State<_PinEntryView> createState() => _PinEntryViewState();
}

class _PinEntryViewState extends State<_PinEntryView>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _isUnlocking = false;
  bool _hasError = false;
  int _attempts = 0;
  String? _errorMessage;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onDigit(int digit) {
    if (_isUnlocking) return;
    HapticFeedback.lightImpact();
    setState(() {
      if (_pin.length < 4) {
        _pin += digit.toString();
        _hasError = false;
        _errorMessage = null;
      }
    });

    if (_pin.length == 4) {
      _tryUnlock();
    }
  }

  void _onBackspace() {
    if (_isUnlocking) return;
    HapticFeedback.lightImpact();
    setState(() {
      if (_pin.isNotEmpty) {
        _pin = _pin.substring(0, _pin.length - 1);
      }
      _hasError = false;
      _errorMessage = null;
    });
  }

  Future<void> _tryUnlock() async {
    setState(() {
      _isUnlocking = true;
      _errorMessage = null;
    });
    final success = await widget.onUnlock(_pin);
    if (!success && mounted) {
      _attempts++;
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);
      // Use backend error if available, otherwise generic message
      final backendError = widget.errorText;
      String msg;
      if (backendError != null && backendError.contains('locked')) {
        msg = backendError;
      } else {
        final remaining = 5 - _attempts;
        msg = remaining > 0
            ? 'Wrong passcode. $remaining attempt${remaining == 1 ? '' : 's'} remaining.'
            : 'Too many attempts. Please wait.';
      }
      setState(() {
        _hasError = true;
        _pin = '';
        _isUnlocking = false;
        _errorMessage = msg;
      });
    } else if (mounted) {
      setState(() => _isUnlocking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock, size: 64, color: _snapYellow),
          const SizedBox(height: 24),
          const Text(
            'Enter Passcode',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 32),
          // Animated PIN dots
          AnimatedBuilder(
            animation: _shakeAnimation,
            builder: (context, child) {
              final offset = _hasError
                  ? (1 - _shakeAnimation.value) * 20 * (_shakeAnimation.value * 2 - 1)
                  : 0.0;
              return Transform.translate(
                offset: Offset(offset, 0),
                child: _PinDots(filledCount: _pin.length, hasError: _hasError),
              );
            },
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.errorColor, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 32),
          if (_isUnlocking)
            const CircularProgressIndicator(color: _snapYellow)
          else
            _NumberPad(onDigit: _onDigit, onBackspace: _onBackspace),
        ],
      ),
    );
  }
}

// ── Vault Memories View ──

class _VaultMemoriesView extends StatelessWidget {
  final MemoryProvider memoryProvider;

  const _VaultMemoriesView({required this.memoryProvider});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Lock button header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${memoryProvider.vaultMemories.length} Private Memories',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
              TextButton.icon(
                onPressed: () => memoryProvider.lockVault(),
                icon: const Icon(Icons.lock, size: 16, color: _snapYellow),
                label:
                    const Text('Lock', style: TextStyle(color: _snapYellow)),
              ),
            ],
          ),
        ),
        Expanded(
          child: memoryProvider.vaultMemories.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () =>
                      memoryProvider.loadVaultMemories(refresh: true),
                  color: _snapYellow,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(2),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 2,
                      crossAxisSpacing: 2,
                    ),
                    itemCount: memoryProvider.vaultMemories.length,
                    itemBuilder: (context, index) {
                      final memory = memoryProvider.vaultMemories[index];
                      return _MemoryTile(
                        memory: memory,
                        onTap: () => context.push('/memories/${memory.id}', extra: {'isVault': true}),
                        onLongPress: () =>
                            _showVaultMemoryOptions(context, memory),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 64, color: _snapYellow),
            SizedBox(height: 24),
            Text(
              'Your private memories are safe here',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Long press on any snap and select\n"Move to My Eyes Only"',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  void _showVaultMemoryOptions(BuildContext context, Memory memory) {
    HapticFeedback.mediumImpact();
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
            ListTile(
              leading: const Icon(Icons.lock_open, color: _snapYellow),
              title: const Text('Move out of My Eyes Only',
                  style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(ctx);
                final success = await memoryProvider.moveFromVault(memory.id);
                if (context.mounted && success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Moved to regular memories'),
                      backgroundColor: AppTheme.successColor,
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: AppTheme.errorColor),
              title: const Text('Delete',
                  style: TextStyle(color: AppTheme.errorColor)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, memory);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Memory memory) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Delete Memory?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await memoryProvider.deleteMemory(memory.id);
              await memoryProvider.loadVaultMemories(refresh: true);
            },
            child:
                const Text('Delete', style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _PinDots extends StatelessWidget {
  final int filledCount;
  final bool hasError;

  const _PinDots({required this.filledCount, this.hasError = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final isFilled = index < filledCount;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: isFilled ? 18 : 16,
          height: isFilled ? 18 : 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled
                ? (hasError ? AppTheme.errorColor : Colors.white)
                : Colors.transparent,
            border: Border.all(
              color: hasError
                  ? AppTheme.errorColor
                  : (isFilled ? Colors.white : Colors.grey[700]!),
              width: 2,
            ),
          ),
        );
      }),
    );
  }
}

class _NumberPad extends StatelessWidget {
  final void Function(int digit) onDigit;
  final VoidCallback onBackspace;

  const _NumberPad({required this.onDigit, required this.onBackspace});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Column(
        children: [
          _buildRow([1, 2, 3]),
          const SizedBox(height: 16),
          _buildRow([4, 5, 6]),
          const SizedBox(height: 16),
          _buildRow([7, 8, 9]),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 72, height: 72),
              _NumberButton(digit: 0, onPressed: () => onDigit(0)),
              SizedBox(
                width: 72,
                height: 72,
                child: IconButton(
                  onPressed: onBackspace,
                  icon: const Icon(Icons.backspace_outlined,
                      color: Colors.white, size: 24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRow(List<int> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits
          .map((d) => _NumberButton(digit: d, onPressed: () => onDigit(d)))
          .toList(),
    );
  }
}

class _NumberButton extends StatelessWidget {
  final int digit;
  final VoidCallback onPressed;

  const _NumberButton({required this.digit, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            digit.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CAMERA ROLL DETAIL SCREEN
// ═══════════════════════════════════════════════════════════════════════════

class _CameraRollDetailScreen extends StatefulWidget {
  final AssetEntity asset;
  const _CameraRollDetailScreen({required this.asset});
  @override
  State<_CameraRollDetailScreen> createState() => _CameraRollDetailScreenState();
}

class _CameraRollDetailScreenState extends State<_CameraRollDetailScreen> {
  File? _file;
  VideoPlayerController? _videoController;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSending = false;
  bool _showControls = true;
  bool _videoError = false;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    final file = await widget.asset.file;
    if (!mounted || file == null) return;
    _file = file;
    if (widget.asset.type == AssetType.video) {
      try {
        _videoController = VideoPlayerController.file(file);
        await _videoController!.initialize();
        await _videoController!.setLooping(true);
        await _videoController!.play();
      } catch (_) {
        _videoError = true;
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isLoading || _file == null)
              const Center(child: CircularProgressIndicator(color: _snapYellow))
            else if (widget.asset.type == AssetType.video)
              _buildVideoView()
            else
              InteractiveViewer(
                minScale: 1, maxScale: 3,
                child: Image.file(_file!, fit: BoxFit.contain),
              ),
            if (_showControls)
              Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),
            if (_showControls)
              Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),
            if (_isSaving || _isSending)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(_isSending ? 'Sending...' : 'Saving to Memories...',
                          style: const TextStyle(color: Colors.white, fontSize: 16)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoView() {
    if (_videoError || _videoController == null || !_videoController!.value.isInitialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, color: Colors.white54, size: 64),
            SizedBox(height: 12),
            Text('Unable to play video', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_videoController!),
            GestureDetector(
              onTap: () {
                if (_videoController!.value.isPlaying) {
                  _videoController!.pause();
                } else {
                  _videoController!.play();
                }
                setState(() {});
              },
              child: Container(
                color: Colors.transparent,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _videoController!.value.isPlaying ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: 64, height: 64,
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const Spacer(),
              Text(_formatAssetDate(widget.asset.createDateTime),
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const Spacer(),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionBtn(Icons.send_rounded, 'Send', _sendToChat),
              _buildActionBtn(Icons.bookmark_border, 'Save', _saveToMemories),
              _buildActionBtn(Icons.delete_outline, 'Delete', _confirmDelete, color: AppTheme.errorColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBtn(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50, height: 50,
            decoration: const BoxDecoration(color: Colors.white12, shape: BoxShape.circle),
            child: Icon(icon, color: color ?? Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color ?? Colors.white, fontSize: 11)),
        ],
      ),
    );
  }

  String _formatAssetDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date.weekday - 1];
    }
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _saveToMemories() async {
    if (_file == null) return;
    setState(() => _isSaving = true);
    try {
      final api = ApiService();
      final uploadResponse = await api.uploadMedia(_file!.path);
      final mediaUrl = uploadResponse.data['data']['media']['url'] as String;
      final memoryProvider = MemoryProvider();
      final success = await memoryProvider.saveMemory(
        mediaUrl: mediaUrl,
        mediaType: widget.asset.type == AssetType.video ? 'VIDEO' : 'IMAGE',
      );
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success ? 'Saved to Memories!' : 'Failed to save'),
          backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        final msg = e is AppException ? e.message : ErrorHandler.handle(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $msg'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _sendToChat() async {
    if (_file == null) return;
    try {
      final api = ApiService();
      final response = await api.getFriends();
      final friends = (response.data['data']['friends'] as List? ?? [])
          .map((f) => f as Map<String, dynamic>).toList();
      if (!mounted) return;
      if (friends.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No friends to send to'), backgroundColor: AppTheme.cardColor),
        );
        return;
      }
      _showRecipientPicker(friends);
    } catch (e) {
      if (mounted) {
        final msg = e is AppException ? e.message : ErrorHandler.handle(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load friends: $msg'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  void _showRecipientPicker(List<Map<String, dynamic>> friends) {
    final selectedRecipients = <String>{};
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              children: [
                Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text('Send To',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: friends.length,
                    itemBuilder: (context, index) {
                      final friend = friends[index];
                      final id = friend['id'] as String;
                      final username = friend['username'] as String? ?? 'Unknown';
                      final displayName = friend['displayName'] as String? ?? username;
                      final profilePhoto = friend['profilePhotoUrl'] as String?;
                      final isSelected = selectedRecipients.contains(id);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.surfaceColor,
                          backgroundImage: profilePhoto != null ? NetworkImage(profilePhoto) : null,
                          child: profilePhoto == null
                              ? Text(displayName[0].toUpperCase(), style: const TextStyle(color: Colors.white))
                              : null,
                        ),
                        title: Text(displayName, style: const TextStyle(color: Colors.white)),
                        subtitle: Text('@$username', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        trailing: Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? _snapYellow : Colors.transparent,
                            border: Border.all(color: isSelected ? _snapYellow : Colors.white38, width: 2),
                          ),
                          child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
                        ),
                        onTap: () {
                          setSheetState(() {
                            if (isSelected) { selectedRecipients.remove(id); }
                            else { selectedRecipients.add(id); }
                          });
                        },
                      );
                    },
                  ),
                ),
                if (selectedRecipients.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _snapYellow,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _sendToRecipients(selectedRecipients.toList());
                        },
                        child: Text('Send (${selectedRecipients.length})',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendToRecipients(List<String> recipientIds) async {
    if (_file == null) return;
    setState(() => _isSending = true);
    try {
      final api = ApiService();
      final uploadResponse = await api.uploadMedia(_file!.path);
      final mediaUrl = uploadResponse.data['data']['media']['url'] as String;
      await api.sendSnap(
        recipientIds: recipientIds,
        mediaUrl: mediaUrl,
        mediaType: widget.asset.type == AssetType.video ? 'VIDEO' : 'IMAGE',
      );
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sent!'), backgroundColor: AppTheme.successColor),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        final msg = e is AppException ? e.message : ErrorHandler.handle(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: $msg'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Delete Photo?', style: TextStyle(color: Colors.white)),
        content: const Text('This will permanently delete this photo from your device.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () { Navigator.pop(ctx); _deleteAsset(); },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAsset() async {
    try {
      final result = await PhotoManager.editor.deleteWithIds([widget.asset.id]);
      if (mounted) {
        if (result.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo deleted'), backgroundColor: AppTheme.successColor),
          );
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete'), backgroundColor: AppTheme.errorColor),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }
}