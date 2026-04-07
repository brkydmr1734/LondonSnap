import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:intl/intl.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:dio/dio.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/memories/models/memory_models.dart';
import 'package:londonsnaps/features/memories/providers/memory_provider.dart';

class MemoryDetailScreen extends StatefulWidget {
  final String memoryId;
  final bool isVault;

  const MemoryDetailScreen({super.key, required this.memoryId, this.isVault = false});

  @override
  State<MemoryDetailScreen> createState() => _MemoryDetailScreenState();
}

class _MemoryDetailScreenState extends State<MemoryDetailScreen> {
  final MemoryProvider _memoryProvider = MemoryProvider();
  late PageController _pageController;
  VideoPlayerController? _videoController;
  int _currentIndex = 0;
  bool _showControls = true;
  bool _isDeleting = false;
  bool _isResharing = false;
  bool _isSaving = false;
  bool _isEditing = false;

  /// The correct memory list based on source (vault vs regular)
  List<Memory> get _sourceMemories => widget.isVault
      ? _memoryProvider.vaultMemories
      : _memoryProvider.memories;

  @override
  void initState() {
    super.initState();
    _memoryProvider.addListener(_onUpdate);
    _currentIndex = _sourceMemories.indexWhere((m) => m.id == widget.memoryId);
    if (_currentIndex < 0) _currentIndex = 0;
    _pageController = PageController(initialPage: _currentIndex);
    _initVideoIfNeeded(_currentIndex);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _initVideoIfNeeded(int index) async {
    if (index < 0 || index >= _sourceMemories.length) return;
    
    final memory = _sourceMemories[index];
    if (memory.isVideo) {
      _videoController?.dispose();
      _videoController = VideoPlayerController.networkUrl(Uri.parse(memory.mediaUrl));
      await _videoController!.initialize();
      await _videoController!.setLooping(true);
      await _videoController!.play();
      if (mounted) setState(() {});
    } else {
      _videoController?.dispose();
      _videoController = null;
    }
  }

  @override
  void dispose() {
    _memoryProvider.removeListener(_onUpdate);
    _pageController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Memory? get _currentMemory {
    if (_currentIndex >= 0 && _currentIndex < _sourceMemories.length) {
      return _sourceMemories[_currentIndex];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_sourceMemories.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(
          child: Text('Memory not found', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Page view for swiping
            PageView.builder(
              controller: _pageController,
              itemCount: _sourceMemories.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
                _initVideoIfNeeded(index);
              },
              itemBuilder: (context, index) {
                final memory = _sourceMemories[index];
                return _buildMemoryView(memory, index == _currentIndex);
              },
            ),

            // Top controls
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopBar(),
              ),

            // Bottom controls
            if (_showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomBar(),
              ),

            // Loading overlay
            if (_isDeleting || _isResharing || _isSaving)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        _isDeleting ? 'Deleting...' : _isResharing ? 'Sharing to Story...' : 'Saving to device...',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryView(Memory memory, bool isActive) {
    if (memory.isVideo && isActive && _videoController != null) {
      return Center(
        child: _videoController!.value.isInitialized
            ? AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_videoController!),
                    // Play/pause overlay
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
                              width: 64,
                              height: 64,
                              decoration: const BoxDecoration(
                                color: Colors.black45,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : const CircularProgressIndicator(color: Colors.white),
      );
    }

    // Image
    return InteractiveViewer(
      minScale: 1,
      maxScale: 3,
      child: CachedNetworkImage(
        imageUrl: memory.mediaUrl,
        fit: BoxFit.contain,
        placeholder: (context, url) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        errorWidget: (context, url, error) => const Center(
          child: Icon(Icons.broken_image, color: AppTheme.textMuted, size: 64),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final memory = _currentMemory;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
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
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => context.pop(),
              ),
              const Spacer(),
              // "On This Day" badge
              if (memory?.isOnThisDay == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('📸', style: TextStyle(fontSize: 14)),
                      SizedBox(width: 4),
                      Text(
                        'On This Day',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.info_outline, color: Colors.white),
                onPressed: () => _showInfoSheet(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final memory = _currentMemory;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Caption
            if (memory?.caption != null && memory!.caption!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  memory.caption!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            // Date
            if (memory != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _formatDate(memory.takenAt),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    icon: Icons.auto_stories,
                    label: 'Share',
                    onTap: () => _reshareAsStory(),
                  ),
                  _buildActionButton(
                    icon: Icons.download,
                    label: 'Save',
                    onTap: () => _saveToDevice(),
                  ),
                  _buildActionButton(
                    icon: Icons.edit,
                    label: 'Edit',
                    onTap: () => _showEditSheet(),
                  ),
                  _buildActionButton(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    color: AppTheme.errorColor,
                    onTap: () => _confirmDelete(),
                  ),
                ],
              ),
            ),

            // Page indicator
            if (_sourceMemories.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_currentIndex + 1} / ${_sourceMemories.length}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white12,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color ?? Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today at ${DateFormat.jm().format(date)}';
    } else if (diff.inDays == 1) {
      return 'Yesterday at ${DateFormat.jm().format(date)}';
    } else if (diff.inDays < 7) {
      return DateFormat('EEEE \'at\' h:mm a').format(date);
    } else if (date.year == now.year) {
      return DateFormat('MMMM d \'at\' h:mm a').format(date);
    } else {
      return DateFormat('MMMM d, yyyy \'at\' h:mm a').format(date);
    }
  }

  void _showInfoSheet() {
    final memory = _currentMemory;
    if (memory == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Memory Info',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              _buildInfoRow(Icons.calendar_today, 'Date',
                  DateFormat('MMMM d, yyyy').format(memory.takenAt)),
              _buildInfoRow(Icons.access_time, 'Time',
                  DateFormat('h:mm a').format(memory.takenAt)),
              _buildInfoRow(
                memory.isVideo ? Icons.videocam : Icons.photo,
                'Type',
                memory.isVideo ? 'Video' : 'Photo',
              ),
              if (memory.location != null)
                _buildInfoRow(Icons.location_on, 'Location', memory.location!),
              if (memory.album != null)
                _buildInfoRow(Icons.folder, 'Album', memory.album!.name),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryColor),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _reshareAsStory() async {
    final memory = _currentMemory;
    if (memory == null) return;

    setState(() => _isResharing = true);
    
    final success = await _memoryProvider.reshareMemory(memory.id);
    
    if (mounted) {
      setState(() => _isResharing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Shared to your story!' : 'Failed to share'),
          backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
        ),
      );
    }
  }

  void _confirmDelete() {
    final memory = _currentMemory;
    if (memory == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Delete Memory?'),
        content: const Text(
          'This memory will be permanently deleted. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteMemory();
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMemory() async {
    final memory = _currentMemory;
    if (memory == null) return;

    setState(() => _isDeleting = true);
    
    final success = await _memoryProvider.deleteMemory(memory.id);
    
    if (mounted) {
      setState(() => _isDeleting = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Memory deleted'),
            backgroundColor: AppTheme.successColor,
          ),
        );
        // If no more memories, go back
        if (_sourceMemories.isEmpty) {
          context.pop();
        } else {
          // Adjust index if needed
          if (_currentIndex >= _sourceMemories.length) {
            _currentIndex = _sourceMemories.length - 1;
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete memory'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _saveToDevice() async {
    final memory = _currentMemory;
    if (memory == null) return;

    setState(() => _isSaving = true);

    try {
      // Download the file first
      final response = await Dio().get(
        memory.mediaUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      // Save to gallery
      final result = await ImageGallerySaver.saveImage(
        response.data,
        quality: 100,
        name: 'londonsnaps_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (mounted) {
        setState(() => _isSaving = false);
        final success = result['isSuccess'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Saved to your photos!' : 'Failed to save'),
            backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save. Please check your permissions.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  void _showEditSheet() {
    final memory = _currentMemory;
    if (memory == null) return;

    final captionController = TextEditingController(text: memory.caption ?? '');
    String? selectedAlbumId = memory.album?.id;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Edit Memory',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: captionController,
                  decoration: const InputDecoration(
                    labelText: 'Caption',
                    hintText: 'Add a caption...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  maxLength: 500,
                ),
                const SizedBox(height: 16),
                // Album picker
                DropdownButtonFormField<String?>(
                  initialValue: selectedAlbumId,
                  decoration: const InputDecoration(
                    labelText: 'Album',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No Album'),
                    ),
                    ..._memoryProvider.albums.map((album) => DropdownMenuItem<String?>(
                      value: album.id,
                      child: Text(album.name),
                    )),
                  ],
                  onChanged: (value) {
                    setSheetState(() => selectedAlbumId = value);
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isEditing
                        ? null
                        : () async {
                            final navigator = Navigator.of(ctx);
                            final messenger = ScaffoldMessenger.of(context);
                            
                            setSheetState(() => _isEditing = true);
                            final updatedMemory = await _memoryProvider.updateMemory(
                              memory.id,
                              caption: captionController.text.trim().isEmpty
                                  ? null
                                  : captionController.text.trim(),
                              albumId: selectedAlbumId,
                            );
                            setSheetState(() => _isEditing = false);

                            navigator.pop();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(updatedMemory != null
                                    ? 'Memory updated!'
                                    : 'Failed to update memory'),
                                backgroundColor: updatedMemory != null
                                    ? AppTheme.successColor
                                    : AppTheme.errorColor,
                              ),
                            );
                          },
                    child: _isEditing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save Changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
