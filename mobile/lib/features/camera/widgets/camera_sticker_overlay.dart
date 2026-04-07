import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'overlay_models.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Snapchat-style Sticker Picker (full-height bottom sheet)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class StickerPicker extends StatefulWidget {
  final Function(String emoji) onStickerSelected;

  const StickerPicker({super.key, required this.onStickerSelected});

  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  List<String> _recentEmojis = [];
  String _searchQuery = '';

  static const _recentKey = 'recent_emojis';

  final List<String> _categoryNames = ['Recent', ...StickerCategories.categories.keys];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categoryNames.length, vsync: this);
    _loadRecentEmojis();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentEmojis() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_recentKey);
    if (saved != null && mounted) {
      setState(() => _recentEmojis = saved);
    }
  }

  Future<void> _addToRecent(String emoji) async {
    _recentEmojis.remove(emoji);
    _recentEmojis.insert(0, emoji);
    if (_recentEmojis.length > 30) _recentEmojis = _recentEmojis.sublist(0, 30);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentKey, _recentEmojis);
  }

  void _selectEmoji(String emoji) {
    HapticFeedback.lightImpact();
    _addToRecent(emoji);
    widget.onStickerSelected(emoji);
    Navigator.pop(context);
  }

  List<String> _getFilteredEmojis() {
    if (_searchQuery.isEmpty) return [];
    final allEmojis = <String>{};
    for (final list in StickerCategories.categories.values) {
      allEmojis.addAll(list);
    }
    // Simple text match — emoji search is limited but functional
    return allEmojis.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search stickers',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 15),
                  prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.4), size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
              ),
            ),
          ),

          // Category tabs
          if (_searchQuery.isEmpty)
            TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: Colors.white,
              indicatorWeight: 2,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tabs: _categoryNames.map((name) => Tab(text: name)).toList(),
            ),

          // Emoji grid
          Expanded(
            child: _searchQuery.isNotEmpty
                ? _buildSearchResults()
                : TabBarView(
                    controller: _tabController,
                    children: _categoryNames.map((name) {
                      final emojis = name == 'Recent'
                          ? _recentEmojis
                          : StickerCategories.categories[name] ?? [];
                      if (emojis.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                name == 'Recent' ? Icons.history : Icons.emoji_emotions_outlined,
                                color: Colors.white24,
                                size: 40,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                name == 'Recent' ? 'No recent stickers' : 'No stickers',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
                              ),
                            ],
                          ),
                        );
                      }
                      return _buildEmojiGrid(emojis);
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    final emojis = _getFilteredEmojis();
    if (emojis.isEmpty) {
      return const Center(
        child: Text('No results', style: TextStyle(color: Colors.white30, fontSize: 14)),
      );
    }
    return _buildEmojiGrid(emojis);
  }

  Widget _buildEmojiGrid(List<String> emojis) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: emojis.length,
      itemBuilder: (context, index) {
        final emoji = emojis[index];
        return GestureDetector(
          onTap: () => _selectEmoji(emoji),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 28)),
            ),
          ),
        );
      },
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Draggable Sticker Item (with trash zone support)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class DraggableStickerItem extends StatefulWidget {
  final StickerItem item;
  final Size containerSize;
  final Function(StickerItem) onUpdate;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onDragStateChanged;

  const DraggableStickerItem({
    super.key,
    required this.item,
    required this.containerSize,
    required this.onUpdate,
    this.onDelete,
    this.onDragStateChanged,
  });

  @override
  State<DraggableStickerItem> createState() => _DraggableStickerItemState();
}

class _DraggableStickerItemState extends State<DraggableStickerItem> {
  late Offset _position;
  late double _scale;
  late double _rotation;
  double _baseScale = 1.0;
  double _baseRotation = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _position = widget.item.position;
    _scale = widget.item.scale;
    _rotation = widget.item.rotation;
  }

  @override
  void didUpdateWidget(DraggableStickerItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _position = widget.item.position;
      _scale = widget.item.scale;
      _rotation = widget.item.rotation;
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseScale = _scale;
    _baseRotation = _rotation;
    _isDragging = true;
    widget.onDragStateChanged?.call(true);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      final dx = details.focalPointDelta.dx / widget.containerSize.width;
      final dy = details.focalPointDelta.dy / widget.containerSize.height;
      _position = Offset(
        (_position.dx + dx).clamp(0.0, 1.0),
        (_position.dy + dy).clamp(0.0, 1.0),
      );
      if (details.scale != 1.0) {
        _scale = (_baseScale * details.scale).clamp(0.2, 5.0);
      }
      if (details.rotation != 0.0) {
        _rotation = _baseRotation + details.rotation;
      }
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _isDragging = false;
    widget.onDragStateChanged?.call(false);

    // Check trash zone (bottom 15%)
    if (_position.dy > 0.85 && widget.onDelete != null) {
      HapticFeedback.heavyImpact();
      widget.onDelete!();
      return;
    }

    widget.onUpdate(widget.item.copyWith(
      position: _position,
      scale: _scale,
      rotation: _rotation,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final x = _position.dx * widget.containerSize.width;
    final y = _position.dy * widget.containerSize.height;

    return Positioned(
      left: x,
      top: y,
      child: GestureDetector(
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: AnimatedScale(
          scale: _isDragging ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Transform.rotate(
            angle: _rotation,
            child: Transform.scale(
              scale: _scale,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: Container(
                  decoration: _isDragging
                      ? BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        )
                      : null,
                  child: Text(
                    widget.item.emoji,
                    style: const TextStyle(fontSize: 64),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Show Sticker Picker
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Future<void> showStickerPicker(
  BuildContext context,
  Function(String emoji) onStickerSelected,
) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => StickerPicker(onStickerSelected: onStickerSelected),
  );
}
